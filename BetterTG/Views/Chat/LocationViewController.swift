// LocationViewController.swift

import CoreLocation
import MapKit
import TDLibKit
import UIKit

// MARK: - LocationViewSubject

/// The message Telegram's LocationViewController opens on: a location, a venue or a live location, or a bare
/// location from rich content.
struct LocationViewSubject {
    let coordinate: CLLocationCoordinate2D
    /// A venue message's place, which gives the info row its title, address and icon.
    let venue: LocationPickerVenue?
    /// A live location message, around which the viewer lists the chat's live locations.
    let liveMessage: Message?

    init?(message: Message) {
        switch message.content {
        case .messageLocation(let content):
            self.coordinate = CLLocationCoordinate2D(
                latitude: content.location.latitude,
                longitude: content.location.longitude,
            )
            self.venue = nil
            self.liveMessage = nil
        case .messageVenue(let content):
            let place = LocationPickerVenue(venue: content.venue)
            self.coordinate = place.coordinate
            self.venue = place
            self.liveMessage = nil
        case .messageLiveLocation(let content):
            self.coordinate = CLLocationCoordinate2D(
                latitude: content.location.location.latitude,
                longitude: content.location.location.longitude,
            )
            self.venue = nil
            self.liveMessage = message
        default:
            return nil
        }
    }

    init(location: Location) {
        self.coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        self.venue = nil
        self.liveMessage = nil
    }
}

// MARK: - LocationDirections

/// Telegram's OpenInLocationDirections for the driving and walking buttons.
private enum LocationDirections {
    case driving
    case walking

    var transportType: MKDirectionsTransportType {
        self == .driving ? .automobile : .walking
    }

    var launchMode: String {
        self == .driving ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking
    }

    var googleMode: String {
        self == .driving ? "driving" : "walking"
    }
}

// MARK: - LocationTravelTime

/// Telegram's ExpectedTravelTime: MapKit's estimate from the user's location, while it is calculated, or unknown
/// when MapKit has none.
private enum LocationTravelTime: Equatable {
    case calculating
    case unknown
    case ready(TimeInterval)

    /// Telegram's stringForEstimatedDuration.
    @MainActor var text: String? {
        guard case .ready(let time) = self, time > 0 else { return nil }
        let duration = max(time, 60)
        let minutes = Int(duration / 60) % 60
        let hours = Int(duration / 3600)
        if hours >= 24 {
            return L10n.telegramPlural("Map.ETADays", count: Int(duration / (3600 * 24)))
        }
        if hours > 0 {
            if hours == 1, minutes == 0 {
                return L10n.telegramPlural("Map.ETAHours", count: 1)
            }
            return L10n.telegramPlural("Map.ETAHours", count: 10)
                .replacingOccurrences(of: "10", with: String(format: "%ld:%02ld", hours, minutes))
        }
        return L10n.telegramPlural("Map.ETAMinutes", count: minutes)
    }

    /// Telegram's getExpectedTravelTime: MapKit's ETA from the user's location.
    @MainActor static func calculate(to coordinate: CLLocationCoordinate2D, by directions: LocationDirections) async
        -> Self
    {
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil,
        )
        request.transportType = directions.transportType
        request.requestsAlternateRoutes = false
        guard let response = try? await MKDirections(request: request).calculateETA() else { return .unknown }
        return .ready(response.expectedTravelTime)
    }
}

// MARK: - LocationOpenInOption

/// An app of Telegram's OpenInOptions for a location (allOpenInOptions, `.location`): Apple Maps, opened through
/// MapKit, and the apps that open the place or a route to it.
private struct LocationOpenInOption {
    /// Telegram's urlQueryValueAllowed: a query value's characters without the query's separators.
    private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?"))

    let title: String
    /// Nil for Apple Maps.
    let url: URL?

    /// availableOpenInOptions: Apple Maps and the apps that `canOpenURL` reports, in Telegram's order.
    @MainActor static func available(
        coordinate: CLLocationCoordinate2D,
        venue: LocationPickerVenue?,
        directions: LocationDirections?,
    ) -> [Self] {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let name = venue?.title.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? ""
        let address = venue?.address.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? ""
        var options = [Self]()
        func add(_ title: String, scheme: String, _ link: String) {
            guard let schemeURL = URL(string: "\(scheme)://"), UIApplication.shared.canOpenURL(schemeURL),
                  let url = URL(string: link) else { return }
            options.append(Self(title: title, url: url))
        }

        if directions == nil, let venue, venue.provider == "foursquare", !venue.id.isEmpty {
            add("Foursquare", scheme: "foursquare", "foursquare://venues/\(venue.id)")
        }
        options.append(Self(title: "Maps", url: nil))
        // Google Maps comes back to the app through its x-callback; BetterTG has no resume link for it.
        if let directions {
            add(
                "Google Maps",
                scheme: "comgooglemaps-x-callback",
                "comgooglemaps-x-callback://?daddr=\(lat),\(lon)&directionsmode=\(directions.googleMode)"
                    + "&x-source=BetterTG",
            )
        } else if let venue, venue.provider == "gplaces", !venue.id.isEmpty {
            add(
                "Google Maps",
                scheme: "comgooglemaps-x-callback",
                "https://www.google.com/maps/search/?api=1&query=\(address)&query_place_id=\(venue.id)",
            )
        } else {
            add(
                "Google Maps",
                scheme: "comgooglemaps-x-callback",
                "comgooglemaps-x-callback://?center=\(lat),\(lon)&q=\(lat),\(lon)&x-source=BetterTG",
            )
        }
        if directions == nil {
            add("Yango Maps", scheme: "yangomaps", "yangomaps://maps.yango.com/?pt=\(lon),\(lat)&z=16")
            add("Yandex.Maps", scheme: "yandexmaps", "yandexmaps://maps.yandex.ru/?pt=\(lon),\(lat)&z=16")
        } else {
            add("Yango Maps", scheme: "yangomaps", "yangomaps://build_route_on_map?lat_to=\(lat)&lon_to=\(lon)")
            add("Yandex.Maps", scheme: "yandexmaps", "yandexmaps://build_route_on_map?lat_to=\(lat)&lon_to=\(lon)")
        }
        add(
            "Uber",
            scheme: "uber",
            "uber://?client_id=&action=setPickup&pickup=my_location&dropoff[latitude]=\(lat)"
                + "&dropoff[longitude]=\(lon)&dropoff[nickname]=\(name)&dropoff[formatted_address]=\(address)",
        )
        add(
            "Lyft",
            scheme: "lyft",
            "lyft://ridetype?id=lyft&destination[latitude]=\(lat)&destination[longitude]=\(lon)",
        )
        if directions != nil {
            add(
                "Citymapper",
                scheme: "citymapper",
                "citymapper://directions?endcoord=\(lat),\(lon)&endname=\(name)&endaddress=\(address)",
            )
            add("Yandex.Navi", scheme: "yandexnavi", "yandexnavi://build_route_on_map?lat_to=\(lat)&lon_to=\(lon)")
            add("2GIS", scheme: "dgis", "dgis://2gis.ru/routeSearch/to/\(lon),\(lat)/go")
            add(
                "Moovit",
                scheme: "moovit",
                "moovit://directions?dest_lat=\(lat)&dest_lon=\(lon)&dest_name=\(name)&partner_id=Telegram",
            )
            add("Waze", scheme: "waze", "waze://?ll=\(lat),\(lon)&navigate=yes")
        } else {
            add("2GIS", scheme: "dgis", "dgis://2gis.ru/geo/\(lon),\(lat)")
            add("Moovit", scheme: "moovit", "moovit://nearby?lat=\(lat)&lon=\(lon)&partner_id=Telegram")
            add("HERE Maps", scheme: "here-location", "here-location://\(lat),\(lon)")
            add("Waze", scheme: "waze", "waze://?ll=\(lat),\(lon)")
        }
        add("Yandex Go", scheme: "yandextaxi", "yandextaxi://route?end-lat=\(lat)&end-lon=\(lon)")
        add("Yango", scheme: "yangoride", "yangoride://route?end-lat=\(lat)&end-lon=\(lon)")
        add("Rizo GO", scheme: "rizogo", "rizogo://route?end-lat=\(lat)&end-lon=\(lon)")
        return options
    }
}

// MARK: - LocationDirectionsView

/// LocationInfoListItem's and LocationLiveListItem's directions buttons: Get Directions while neither travel time is
/// known, else the driving and walking times, each opening directions.
private final class LocationDirectionsView: UIView {
    var onDirections: ((LocationDirections) -> Void)?

    private let drivingButton = UIButton(type: .system)
    private let walkingButton = UIButton(type: .system)
    private let fontSize: CGFloat

    /// - Parameters:
    ///   - fillsWidth: The info row's buttons share its width; a live location's are as wide as their text.
    init(buttonHeight: CGFloat, fontSize: CGFloat, fillsWidth: Bool) {
        self.fontSize = fontSize
        super.init(frame: .zero)
        let stack = UIStackView(arrangedSubviews: [drivingButton, walkingButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 10
        stack.distribution = fillsWidth ? .fillEqually : .fill
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: buttonHeight),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillsWidth
                ? stack.trailingAnchor.constraint(equalTo: trailingAnchor)
                : stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        for button in [drivingButton, walkingButton] {
            button.isHidden = true
            if !fillsWidth {
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
            }
        }
        drivingButton.addAction(UIAction { [weak self] _ in self?.onDirections?(.driving) }, for: .touchUpInside)
        walkingButton.addAction(UIAction { [weak self] _ in self?.onDirections?(.walking) }, for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Nothing shows while the times are calculated.
    func configure(driving: LocationTravelTime, walking: LocationTravelTime) {
        if driving == .unknown, walking == .unknown {
            show(drivingButton, title: L10n.telegram("Map.GetDirections"), symbol: nil)
            walkingButton.isHidden = true
            return
        }
        if let text = driving.text {
            show(drivingButton, title: text, symbol: "car.fill")
        } else {
            drivingButton.isHidden = true
        }
        if let text = walking.text {
            show(walkingButton, title: text, symbol: "figure.walk")
        } else {
            walkingButton.isHidden = true
        }
    }

    private func show(_ button: UIButton, title: String, symbol: String?) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.image = symbol.flatMap { UIImage(systemName: $0) }
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: fontSize - 2,
            weight: .semibold,
        )
        configuration.imagePadding = 5
        configuration.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: fontSize, weight: .semibold)]),
        )
        configuration.titleLineBreakMode = .byTruncatingTail
        button.configuration = configuration
        button.isHidden = false
    }
}

// MARK: - LocationInfoCell

/// LocationInfoListItem: the place's icon, its title, its address and distance, and the directions buttons.
private final class LocationInfoCell: UITableViewCell {
    static let reuseIdentifier = "LocationInfoCell"

    var onDirections: ((LocationDirections) -> Void)?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let directionsView = LocationDirectionsView(buttonHeight: 50, fontSize: 17, fillsWidth: true)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        directionsView.translatesAutoresizingMaskIntoConstraints = false
        directionsView.onDirections = { [weak self] directions in self?.onDirections?(directions) }
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(directionsView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            directionsView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            directionsView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            directionsView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 18),
            directionsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        icon: UIImage,
        title: String,
        subtitle: String,
        driving: LocationTravelTime,
        walking: LocationTravelTime,
    ) {
        iconView.image = icon
        titleLabel.text = title
        subtitleLabel.text = subtitle
        directionsView.configure(driving: driving, walking: walking)
    }
}

// MARK: - LocationViewController

/// Telegram's LocationViewController for a location or a venue: the map centered on the place's pin, and under it
/// the place's title, its address and distance, and directions by car and on foot with their travel times. Share
/// opens the place in another app or shares a link to it; the map buttons switch the map type and follow the user.
@MainActor final class LocationViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    MKMapViewDelegate, CLLocationManagerDelegate
{
    private enum MapMode: CaseIterable {
        case map
        case satellite
        case hybrid

        var titleKey: String {
            switch self {
            case .map: "Map.Map"
            case .satellite: "Map.Satellite"
            case .hybrid: "Map.Hybrid"
            }
        }

        var configuration: MKMapConfiguration {
            switch self {
            case .map: MKStandardMapConfiguration()
            case .satellite: MKImageryMapConfiguration()
            case .hybrid: MKHybridMapConfiguration()
            }
        }
    }

    private enum Row {
        case info
    }

    /// The message's own pin, kept selected as Telegram's forcedSelection.
    private final class SubjectAnnotation: MKPointAnnotation {}

    private static let subjectAnnotationIdentifier = "LocationSubject"
    /// Telegram's LocationMapNode.viewMapSpan.
    private static let viewSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
    /// The list never covers more of the screen than this.
    private static let maximumListFraction: CGFloat = 0.6

    private let subject: LocationViewSubject
    private let locationManager = CLLocationManager()
    private let mapView = MKMapView()
    private let mapModeButton = UIButton(type: .system)
    private let trackingButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let subjectAnnotation = SubjectAnnotation()
    private let distanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .full
        return formatter
    }()

    private var tableHeightConstraint: NSLayoutConstraint?
    private var contentSizeObservation: NSKeyValueObservation?
    private var mapMode = MapMode.map
    private var userLocation: CLLocation?
    private var accessDenied = false
    /// The venue's address, or the reverse geocoded one; nil while it is looked up.
    private var address: String?
    private var drivingTime = LocationTravelTime.calculating
    private var walkingTime = LocationTravelTime.calculating
    private var geocodeTask: Task<Void, Never>?
    private var travelTimeTask: Task<Void, Never>?
    private var iconCache = [String: UIImage]()

    private var rows: [[Row]] {
        [[.info]]
    }

    init(subject: LocationViewSubject) {
        self.subject = subject
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        geocodeTask?.cancel()
        travelTimeTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Map.LocationTitle")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        let shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), primaryAction: nil)
        shareItem.primaryAction = UIAction { [weak self, weak shareItem] _ in
            guard let shareItem else { return }
            self?.share(from: shareItem)
        }
        shareItem.accessibilityLabel = L10n.telegram("Conversation.ContextMenuShare")
        navigationItem.rightBarButtonItem = shareItem
        configureMap()
        configureTable()
        layoutViews()
        locationManager.delegate = self
        authorizationChanged()
        loadAddress()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableHeight()
    }

    /// Telegram presents the viewer as a sheet.
    func makeNavigationController() -> UINavigationController {
        let navigation = TelegramNavigationController(rootViewController: self)
        navigation.modalPresentationStyle = .pageSheet
        return navigation
    }

    // Table

    func numberOfSections(in _: UITableView) -> Int {
        rows.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows[section].count
    }

    func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 0 ? 12 : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch rows[indexPath.section][indexPath.row] {
        case .info:
            let cell = tableView.dequeueReusableCell(withIdentifier: LocationInfoCell.reuseIdentifier, for: indexPath)
            guard let infoCell = cell as? LocationInfoCell else { return cell }
            infoCell.configure(
                icon: subject.venue.map { icon(symbol: $0.symbolName, color: $0.iconColor) }
                    ?? icon(symbol: "mappin", color: UIColor(rgb: 0x008DF2)),
                title: subject.venue?.title ?? L10n.telegram("Map.Location"),
                subtitle: infoSubtitle(),
                driving: drivingTime,
                walking: walkingTime,
            )
            infoCell.onDirections = { [weak self, weak infoCell] directions in
                self?.requestDirections(directions, name: nil, sourceView: infoCell)
            }
            return infoCell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.section][indexPath.row] {
        case .info:
            goToCoordinate(subject.coordinate)
        }
    }

    // Map

    func mapView(_: MKMapView, didUpdate mapUserLocation: MKUserLocation) {
        guard let location = mapUserLocation.location else { return }
        let isFirstLocation = userLocation == nil
        userLocation = location
        if isFirstLocation {
            calculateTravelTimes()
        }
        reconfigureInfoRow()
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        guard annotation === subjectAnnotation else { return nil }
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: Self.subjectAnnotationIdentifier,
            for: annotation,
        )
        guard let marker = view as? MKMarkerAnnotationView else { return view }
        marker.markerTintColor = subject.venue?.iconColor ?? .systemRed
        marker.glyphImage = subject.venue.flatMap { UIImage(systemName: $0.symbolName) }
        marker.canShowCallout = false
        marker.titleVisibility = .hidden
        marker.displayPriority = .required
        return marker
    }

    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        // LocationPinAnnotation's forcedSelection: the place's pin stays raised.
        guard views.contains(where: { $0.annotation === subjectAnnotation }) else { return }
        mapView.selectAnnotation(subjectAnnotation, animated: false)
    }

    func mapView(_ mapView: MKMapView, didDeselect annotation: any MKAnnotation) {
        guard annotation === subjectAnnotation else { return }
        DispatchQueue.main.async { [weak self, weak mapView] in
            guard let self, let mapView, mapView.selectedAnnotations.isEmpty else { return }
            mapView.selectAnnotation(subjectAnnotation, animated: false)
        }
    }

    func mapView(_: MKMapView, didChange _: MKUserTrackingMode, animated _: Bool) {
        updateTrackingButton()
    }

    // Location access

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }

    private func configureMap() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.preferredConfiguration = mapMode.configuration
        mapView.showsCompass = false
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Self.subjectAnnotationIdentifier,
        )
        mapView.setRegion(MKCoordinateRegion(center: subject.coordinate, span: Self.viewSpan), animated: false)
        subjectAnnotation.coordinate = subject.coordinate
        subjectAnnotation.title = subject.venue?.title
        mapView.addAnnotation(subjectAnnotation)

        // LocationMapHeaderNode's options: the map type, and following the user's location.
        for button in [mapModeButton, trackingButton] {
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = .systemBackground
            configuration.baseForegroundColor = .systemBlue
            configuration.cornerStyle = .capsule
            button.configuration = configuration
            button.translatesAutoresizingMaskIntoConstraints = false
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.15
            button.layer.shadowRadius = 6
            button.layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        mapModeButton.configuration?.image = UIImage(systemName: "map")
        mapModeButton.menu = mapModeMenu()
        mapModeButton.showsMenuAsPrimaryAction = true
        mapModeButton.accessibilityLabel = L10n.telegram("Map.Map")
        trackingButton.addTarget(self, action: #selector(trackingPressed), for: .touchUpInside)
        trackingButton.accessibilityLabel = L10n.betterTG("Accessibility.ShowMyLocation")
        updateTrackingButton()
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(LocationInfoCell.self, forCellReuseIdentifier: LocationInfoCell.reuseIdentifier)
        contentSizeObservation = tableView.observe(\.contentSize) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateTableHeight() }
        }
    }

    private func layoutViews() {
        view.addSubview(mapView)
        view.addSubview(mapModeButton)
        view.addSubview(trackingButton)
        view.addSubview(tableView)
        let tableHeight = tableView.heightAnchor.constraint(equalToConstant: 0)
        tableHeightConstraint = tableHeight
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: tableView.topAnchor),
            mapModeButton.topAnchor.constraint(equalTo: mapView.topAnchor, constant: 12),
            mapModeButton.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -12),
            mapModeButton.widthAnchor.constraint(equalToConstant: 44),
            mapModeButton.heightAnchor.constraint(equalToConstant: 44),
            trackingButton.topAnchor.constraint(equalTo: mapModeButton.bottomAnchor, constant: 8),
            trackingButton.trailingAnchor.constraint(equalTo: mapModeButton.trailingAnchor),
            trackingButton.widthAnchor.constraint(equalToConstant: 44),
            trackingButton.heightAnchor.constraint(equalToConstant: 44),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableHeight,
        ])
    }

    /// The list sits under the map at its content's height, and scrolls once it would cover most of the screen.
    private func updateTableHeight() {
        guard let tableHeightConstraint else { return }
        let insets = tableView.adjustedContentInset
        let maximumHeight = view.bounds.height * Self.maximumListFraction
        let height = min(tableView.contentSize.height + insets.top + insets.bottom, maximumHeight)
        tableView.isScrollEnabled = height >= maximumHeight - 0.5
        guard abs(tableHeightConstraint.constant - height) > 0.5 else { return }
        tableHeightConstraint.constant = height
    }

    private func mapModeMenu() -> UIMenu {
        UIMenu(children: MapMode.allCases.map { mode in
            UIAction(title: L10n.telegram(mode.titleKey), state: mode == mapMode ? .on : .off) { [weak self] _ in
                self?.setMapMode(mode)
            }
        })
    }

    /// Telegram's effectivePresentationData: satellite and hybrid maps turn the screen dark.
    private func setMapMode(_ mode: MapMode) {
        guard mode != mapMode else { return }
        mapMode = mode
        mapView.preferredConfiguration = mode.configuration
        mapModeButton.menu = mapModeMenu()
        let host: UIViewController = navigationController ?? self
        host.overrideUserInterfaceStyle = mode == .map ? .unspecified : .dark
    }

    private func authorizationChanged() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            accessDenied = false
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            accessDenied = false
            mapView.showsUserLocation = true
        default:
            accessDenied = true
            mapView.showsUserLocation = false
            // Without the user's location MapKit has no travel times, and the row offers Get Directions.
            if drivingTime == .calculating || walkingTime == .calculating {
                travelTimeTask?.cancel()
                drivingTime = .unknown
                walkingTime = .unknown
                reconfigureInfoRow()
            }
        }
    }

    /// The tracking button cycles through Telegram's modes: off, following the user, and following their heading.
    @objc private func trackingPressed() {
        guard !accessDenied else {
            presentAccessDenied()
            return
        }
        let mode: MKUserTrackingMode =
            switch mapView.userTrackingMode {
            case .none: .follow
            case .follow: .followWithHeading
            default: .none
            }
        mapView.setUserTrackingMode(mode, animated: true)
        updateTrackingButton()
    }

    private func updateTrackingButton() {
        let symbol =
            switch mapView.userTrackingMode {
            case .follow: "location.fill"
            case .followWithHeading: "location.north.line.fill"
            default: "location"
            }
        trackingButton.configuration?.image = UIImage(systemName: symbol)
    }

    /// Telegram's goToCoordinate: the map centers on the place at its viewing span.
    private func goToCoordinate(_ coordinate: CLLocationCoordinate2D) {
        mapView.setUserTrackingMode(.none, animated: false)
        mapView.setRegion(MKCoordinateRegion(center: coordinate, span: Self.viewSpan), animated: true)
    }

    /// The venue's address, else the reverse geocoded one: Telegram's compactDisplayAddress, the street, else the
    /// city, else the region.
    private func loadAddress() {
        if let venue = subject.venue, !venue.address.isEmpty {
            address = venue.address
            return
        }
        let coordinate = subject.coordinate
        geocodeTask = Task { [weak self] in
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let request = MKReverseGeocodingRequest(location: location) else { return }
            let item = await (try? request.mapItems)?.first
            guard let self, !Task.isCancelled else { return }
            address = item?.address?.shortAddress ?? item?.addressRepresentations?.cityName
                ?? item?.addressRepresentations?.regionName ?? ""
            reconfigureInfoRow()
        }
    }

    /// Telegram's getExpectedTravelTime by car and on foot, once the user's location is known.
    private func calculateTravelTimes() {
        let coordinate = subject.coordinate
        travelTimeTask?.cancel()
        travelTimeTask = Task { [weak self] in
            async let driving = LocationTravelTime.calculate(to: coordinate, by: .driving)
            let walking = await LocationTravelTime.calculate(to: coordinate, by: .walking)
            let drivingResult = await driving
            guard let self, !Task.isCancelled else { return }
            drivingTime = drivingResult
            walkingTime = walking
            reconfigureInfoRow()
        }
    }

    /// LocationViewEntry.info's subtitle: the address (Locating... until it is known) and the distance from the
    /// user, "you are here" within 10 meters.
    private func infoSubtitle() -> String {
        var components = [address ?? L10n.telegram("Map.Locating")]
        if let userLocation {
            let place = CLLocation(latitude: subject.coordinate.latitude, longitude: subject.coordinate.longitude)
            let distance = place.distance(from: userLocation)
            components.append(distance < 10
                ? L10n.telegram("Map.YouAreHere")
                : L10n.telegram("Map.DistanceAway", distanceFormatter.string(fromDistance: distance)))
        }
        return components.filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private func reconfigureInfoRow() {
        guard isViewLoaded else { return }
        var indexPaths = [IndexPath]()
        for (section, sectionRows) in rows.enumerated() {
            for (row, value) in sectionRows.enumerated() {
                if case .info = value {
                    indexPaths.append(IndexPath(row: row, section: section))
                }
            }
        }
        guard !indexPaths.isEmpty else { return }
        tableView.reconfigureRows(at: indexPaths)
    }

    /// Telegram's requestDirections: Apple Maps at once when no other app can open the place, else the apps to choose
    /// from.
    private func requestDirections(_ directions: LocationDirections, name: String?, sourceView: UIView?) {
        let options = LocationOpenInOption.available(
            coordinate: subject.coordinate,
            venue: subject.venue,
            directions: directions,
        )
        guard options.count > 1 else {
            openInMaps(directions: directions, name: name)
            return
        }
        presentOpenIn(options, directions: directions, name: name, share: nil) { popover in
            let source = sourceView ?? self.tableView
            popover.sourceView = source
            popover.sourceRect = source.bounds
        }
    }

    /// Telegram's share button: the apps that open the place, and Share for its link.
    private func share(from item: UIBarButtonItem) {
        let options = LocationOpenInOption.available(
            coordinate: subject.coordinate,
            venue: subject.venue,
            directions: nil,
        )
        let shareAction = UIAlertAction(title: L10n.telegram("Conversation.ContextMenuShare"), style: .default) {
            [weak self] _ in
            self?.shareLink(from: item)
        }
        presentOpenIn(options, directions: nil, name: nil, share: shareAction) { popover in
            popover.sourceItem = item
        }
    }

    private func presentOpenIn(
        _ options: [LocationOpenInOption],
        directions: LocationDirections?,
        name: String?,
        share: UIAlertAction?,
        anchor: (UIPopoverPresentationController) -> Void,
    ) {
        let sheet = UIAlertController(title: L10n.telegram("Map.OpenIn"), message: nil, preferredStyle: .actionSheet)
        for option in options {
            sheet.addAction(UIAlertAction(title: option.title, style: .default) { [weak self] _ in
                if let url = option.url {
                    UIApplication.shared.open(url)
                } else {
                    self?.openInMaps(directions: directions, name: name)
                }
            })
        }
        if let share {
            sheet.addAction(share)
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            anchor(popover)
        }
        present(sheet, animated: true)
    }

    /// Telegram's openLocation action: Apple Maps shows the place under the venue's title or the sharer's name, or
    /// the route to it.
    private func openInMaps(directions: LocationDirections?, name: String?) {
        let coordinate = subject.coordinate
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil,
        )
        item.name = subject.venue?.title ?? name
        if let directions {
            MKMapItem.openMaps(
                with: [MKMapItem.forCurrentLocation(), item],
                launchOptions: [MKLaunchOptionsDirectionsModeKey: directions.launchMode],
            )
        } else {
            item.openInMaps(launchOptions: nil)
        }
    }

    /// ShareController's external share of a location: an Apple Maps link to it.
    private func shareLink(from item: UIBarButtonItem) {
        let coordinates = "\(subject.coordinate.latitude),\(subject.coordinate.longitude)"
        guard let url = URL(string: "https://maps.apple.com/maps?ll=\(coordinates)&q=\(coordinates)&t=m") else {
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceItem = item
        present(activity, animated: true)
    }

    private func presentAccessDenied() {
        let alert = UIAlertController(
            title: L10n.betterTG("Permissions.LocationTitle"),
            message: L10n.betterTG("Permissions.LocationMessage"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Notifications.PermissionsOpenSettings"), style: .default) {
            _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    private func icon(symbol: String, color: UIColor) -> UIImage {
        let key = "\(symbol)|\(color.description)"
        if let cached = iconCache[key] { return cached }
        let size = CGSize(width: 40, height: 40)
        let glyph = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        )?.withTintColor(.white, renderingMode: .alwaysOriginal)
        let image = UIGraphicsImageRenderer(size: size)
            .image { _ in
                color.setFill()
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
                if let glyph {
                    glyph.draw(in: CGRect(
                        x: (size.width - glyph.size.width) / 2,
                        y: (size.height - glyph.size.height) / 2,
                        width: glyph.size.width,
                        height: glyph.size.height,
                    ))
                }
            }
            .withRenderingMode(.alwaysOriginal)
        iconCache[key] = image
        return image
    }
}
