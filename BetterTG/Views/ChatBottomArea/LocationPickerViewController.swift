// LocationPickerViewController.swift

import CoreLocation
import MapKit
import TDLibKit
import UIKit

// MARK: - LocationPickerVenue

/// A place Telegram lists under Choose a place: a venue result of the venue search bot's inline query, whose
/// Foursquare type keys the icon and its color.
struct LocationPickerVenue {
    /// Telegram's `venueColors` (VenueIconResources) for the types this picker sends.
    private static let venueColors: [String: Int] = [
        "building/medical": 0x43B3F4,
        "building/gym": 0x43B3F4,
        "arts_entertainment": 0xAF52DE,
        "travel/hotel": 0x9987FF,
        "building": 0x6E81B2,
        "education": 0xA57348,
        "food": 0xFF9500,
        "nightlife": 0xAF52DE,
        "parks_outdoors": 0x6CC138,
        "shops": 0xFFB300,
        "travel": 0x1C9FFF,
    ]

    let title: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    /// The venue's provider ("foursquare", "gplaces") and its ID there.
    let provider: String
    let id: String
    let type: String

    var location: CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Telegram's `venueIconColor(type:)`: the type's own color, else its general category's.
    var iconColor: UIColor {
        guard !type.isEmpty else { return UIColor(rgb: 0x008DF2) }
        if let color = Self.venueColors[type] { return UIColor(rgb: color) }
        let generalType = type.components(separatedBy: "/").first ?? type
        return UIColor(rgb: Self.venueColors[generalType] ?? 0x6E81B2)
    }

    var symbolName: String {
        switch type {
        case "travel/hotel": "bed.double.fill"
        case "building/medical": "cross.case.fill"
        case "building/gym": "dumbbell.fill"
        default:
            switch type.components(separatedBy: "/").first {
            case "food": "fork.knife"
            case "nightlife": "wineglass.fill"
            case "travel": "tram.fill"
            case "arts_entertainment": "theatermasks.fill"
            case "parks_outdoors": "tree.fill"
            case "education": "graduationcap.fill"
            case "shops": "bag.fill"
            case "building": "building.2.fill"
            default: "mappin"
            }
        }
    }

    /// Telegram's sendVenue: the place goes as the bot gave it.
    var content: InputMessageContent {
        .inputMessageVenue(TDNativeInputMessageVenue(venue: TDNativeVenue(
            location: TDNativeLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                horizontalAccuracy: 0,
            ),
            title: title,
            address: address,
            provider: provider,
            id: id,
            type: type,
        )))
    }

    init(venue: TDNativeVenue) {
        self.title = venue.title
        self.address = venue.address
        self.coordinate = CLLocationCoordinate2D(latitude: venue.location.latitude, longitude: venue.location.longitude)
        self.provider = venue.provider
        self.id = venue.id
        self.type = venue.type
    }
}

// MARK: - LocationPickerViewController

/// Telegram's LocationPickerController in share mode (LocationPickerControllerNode): the map with the user's
/// location, Send My Current Location with its accuracy, a pin moved by dragging the map as Send This Location with
/// its address, a place's pin as Send This Place, Share My Live Location for a chosen period, places nearby or in
/// the dragged-to area from the venue search bot, and a search of addresses and places. LiveLocationManager keeps a
/// sent live location updated.
@MainActor final class LocationPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    MKMapViewDelegate, CLLocationManagerDelegate, UIGestureRecognizerDelegate, UISearchResultsUpdating,
    TelegramNavigationSearchProvider
{
    // MARK: Private

    private enum Selection {
        /// The user's own location (Telegram's `.none`).
        case current
        /// The map is being dragged under the pin.
        case selecting
        case location(CLLocationCoordinate2D, address: String?)
        case venue(LocationPickerVenue)
    }

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
        case send
        case liveLocation
        case placemark(SearchPlacemark)
        case venue(LocationPickerVenue)
        case loading
        case message(String)
    }

    /// An address found for the search query (LocationSearchContainerNode's placemark entries).
    private struct SearchPlacemark {
        let title: String
        let coordinate: CLLocationCoordinate2D
        /// From the map's center when the search ran.
        let distance: CLLocationDistance
    }

    private final class VenueAnnotation: MKPointAnnotation {
        let venue: LocationPickerVenue

        init(venue: LocationPickerVenue) {
            self.venue = venue
            super.init()
            coordinate = venue.coordinate
            title = venue.title
        }
    }

    /// Telegram's live location periods (LocationLiveLocationContextMenu), the last being liveLocationIndefinitePeriod.
    /// The location viewer offers them too.
    static let livePeriods = [15 * 60, 60 * 60 - 1, 8 * 60 * 60, Int(Int32.max)]

    private static let cellIdentifier = "LocationPickerCell"
    private static let loadingCellIdentifier = "LocationPickerLoadingCell"
    private static let venueAnnotationIdentifier = "LocationPickerVenue"
    /// Telegram's LocationMapNode.defaultMapSpan.
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.016, longitudeDelta: 0.016)
    /// TDLib's limit for a location's horizontal accuracy.
    private static let maximumAccuracy: CLLocationAccuracy = 1500

    // MARK: Internal

    let telegramNavigationSearch = UISearchController(searchResultsController: nil)
    /// Called once the picker has gone after Cancel or a send; a swipe down reaches the presenter's delegate.
    var onDismiss: (() -> Void)?
    /// LocationPickerController's `.poll` source: the subtitle under the title, such as "Add location to this
    /// option", and Add This Location for the user's location.
    var pollSubtitle: String?

    private let peerName: String?
    private let allowsLiveLocation: Bool
    /// The chat's client asks the venue search bot; the chat is the inline query's chat.
    private let client: TDLibClient
    private let chatID: Int64
    private let send: (InputMessageContent) -> Void
    private let locationManager = CLLocationManager()
    private let mapView = MKMapView()
    private let pinView = UIImageView()
    private let userLocationButton = UIButton(type: .system)
    private let placesButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let distanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .full
        return formatter
    }()

    private lazy var mapModeItem = UIBarButtonItem(image: UIImage(systemName: "map"), menu: mapModeMenu())
    private var mapMode = MapMode.map
    private var selection = Selection.current
    private var userLocation: CLLocation?
    private var accessDenied = false
    private var centeredOnUser = false
    private var userIsDraggingMap = false
    /// Where the nearby places were asked for (Telegram's throttledUserLocation).
    private var venuesLocation: CLLocation?
    /// Places around the user's location; nil while they load.
    private var nearbyVenues: [LocationPickerVenue]?
    /// Places In This Area: places around a dragged-to location, shown instead of the nearby ones.
    private var areaVenues: [LocationPickerVenue]?
    private var areaCoordinate: CLLocation?
    private var searchingVenuesAround = false
    private var searchQuery = ""
    /// The query's addresses and places; nil while they load.
    private var searchResults: (placemarks: [SearchPlacemark], venues: [LocationPickerVenue])?
    private var venueSearchBotUserID: Int64?
    private var nearbyTask: Task<Void, Never>?
    private var areaTask: Task<Void, Never>?
    private var geocodeTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var iconCache = [String: UIImage]()
    private var didSend = false

    private var isSearching: Bool { !searchQuery.isEmpty }

    /// The send rows, or the found addresses while searching.
    private var actionRows: [Row] {
        guard isSearching else { return allowsLiveLocation ? [.send, .liveLocation] : [.send] }
        return (searchResults?.placemarks ?? []).map { .placemark($0) }
    }

    private var venueRows: [Row] {
        if isSearching {
            guard let searchResults else { return [.loading] }
            guard !searchResults.placemarks.isEmpty || !searchResults.venues.isEmpty else {
                return [.message(L10n.telegram("Map.SearchNoResultsDescription", searchQuery))]
            }
            return searchResults.venues.map { .venue($0) }
        }
        let venues = areaVenues != nil || searchingVenuesAround ? areaVenues : nearbyVenues
        guard let venues else { return [.loading] }
        guard !venues.isEmpty else { return [.message(L10n.telegram("Map.NoPlacesNearby"))] }
        return venues.map { .venue($0) }
    }

    /// The user's accuracy as TDLib takes it, in meters.
    private var userAccuracy: Double {
        guard let accuracy = userLocation?.horizontalAccuracy, accuracy > 0 else { return 0 }
        return min(accuracy, Self.maximumAccuracy)
    }

    /// - Parameters:
    ///   - peerName: The other user's name in a private chat, for the live location description.
    ///   - allowsLiveLocation: Telegram offers live location outside secret chats and Saved Messages.
    ///   - client: The chat's client, which asks the venue search bot.
    ///   - chatID: The chat the venue search bot's inline queries come from.
    ///   - send: Called with the chosen content once the picker has been dismissed.
    init(
        peerName: String?,
        allowsLiveLocation: Bool,
        client: TDLibClient,
        chatID: Int64,
        send: @escaping (InputMessageContent) -> Void,
    ) {
        self.peerName = peerName
        self.allowsLiveLocation = allowsLiveLocation
        self.client = client
        self.chatID = chatID
        self.send = send
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        nearbyTask?.cancel()
        areaTask?.cancel()
        geocodeTask?.cancel()
        searchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Map.ChooseLocationTitle")
        navigationItem.subtitle = pollSubtitle
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelPressed),
        )
        mapModeItem.accessibilityLabel = L10n.telegram("Map.Map")
        navigationItem.rightBarButtonItem = mapModeItem
        let search = telegramNavigationSearch
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = L10n.telegram("Map.Search")
        definesPresentationContext = true
        configureMap()
        configureTable()
        layoutViews()
        locationManager.delegate = self
        authorizationChanged()
    }

    static func livePeriodTitle(_ period: Int) -> String {
        switch period {
        case Int(Int32.max): L10n.telegram("Map.LiveLocationIndefinite")
        case ..<(60 * 60 - 1): L10n.telegramPlural("Map.LiveLocationForMinutes", count: period / 60)
        default: L10n.telegramPlural("Map.LiveLocationForHours", count: (period + 1) / (60 * 60))
        }
    }

    private static func address(of item: MKMapItem) -> String? {
        if let address = item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true),
           !address.isEmpty
        {
            return address
        }
        if let address = item.address?.fullAddress, !address.isEmpty { return address }
        return item.name
    }

    /// Telegram's geocodeLocation(address:) in search: the addresses matching the query, with their distance from the
    /// map's center.
    private static func placemarks(for query: String, around coordinate: CLLocationCoordinate2D) async
        -> [SearchPlacemark]
    {
        guard let request = MKGeocodingRequest(addressString: query) else { return [] }
        let items = await (try? request.mapItems) ?? []
        let center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return items.map { item in
            SearchPlacemark(
                title: item.name ?? address(of: item) ?? L10n.telegram("Map.Unknown"),
                coordinate: item.location.coordinate,
                distance: item.location.distance(from: center),
            )
        }
    }

    // MARK: Table

    func numberOfSections(in _: UITableView) -> Int { 2 }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? actionRows.count : venueRows.count
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard isSearching else { return section == 1 ? L10n.telegram("Map.ChooseAPlace").uppercased() : nil }
        // LocationSearchContainerNode's mapAddress and nearbyVenues headers.
        guard let searchResults else { return nil }
        if section == 0 {
            return searchResults.placemarks.isEmpty ? nil : L10n.telegram("Map.AddressOnMap").uppercased()
        }
        return searchResults.venues.isEmpty ? nil : L10n.telegram("Map.PlacesNearby").uppercased()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = row(at: indexPath)
        if case .loading = row {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.loadingCellIdentifier, for: indexPath)
            if cell.contentView.subviews.isEmpty {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(spinner)
                NSLayoutConstraint.activate([
                    spinner.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
                    spinner.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                    cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
                ])
            }
            (cell.contentView.subviews.first as? UIActivityIndicatorView)?.startAnimating()
            cell.selectionStyle = .none
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.secondaryTextProperties.color = .secondaryLabel
        configuration.imageProperties.maximumSize = CGSize(width: 40, height: 40)
        configuration.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40)
        cell.selectionStyle = .default
        switch row {
        case .send:
            let (title, subtitle) = sendRowText()
            configuration.text = title
            configuration.secondaryText = subtitle
            configuration.textProperties.color = .tintColor
            configuration.image = icon(symbol: "location.fill", color: .systemBlue)
        case .liveLocation:
            configuration.text = L10n.telegram("Map.ShareLiveLocation")
            configuration.secondaryText = L10n.telegram("Map.ShareLiveLocationHelp")
            configuration.textProperties.color = .tintColor
            configuration.image = icon(symbol: "dot.radiowaves.left.and.right", color: UIColor(rgb: 0x6CC138))
        case .placemark(let placemark):
            configuration.text = placemark.title
            configuration.secondaryText = L10n.telegram(
                "Map.DistanceAway",
                distanceFormatter.string(fromDistance: placemark.distance),
            )
            configuration.image = icon(symbol: "mappin", color: UIColor(rgb: 0x008DF2))
        case .venue(let venue):
            configuration.text = venue.title
            configuration.secondaryText = venue.address
            configuration.image = icon(symbol: venue.symbolName, color: venue.iconColor)
        case .message(let text):
            configuration = UIListContentConfiguration.cell()
            configuration.text = text
            configuration.textProperties.color = .secondaryLabel
            configuration.textProperties.alignment = .center
            cell.selectionStyle = .none
        case .loading:
            break
        }
        cell.contentConfiguration = configuration
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch row(at: indexPath) {
        case .send:
            sendSelection()
        case .liveLocation:
            shareLiveLocation(from: tableView.cellForRow(at: indexPath))
        case .placemark(let placemark):
            goToCoordinate(placemark.coordinate)
        case .venue(let venue):
            finish(with: venue.content)
        case .loading, .message:
            break
        }
    }

    // MARK: Map

    func mapView(_ mapView: MKMapView, didUpdate mapUserLocation: MKUserLocation) {
        guard let location = mapUserLocation.location else { return }
        userLocation = location
        if case .current = selection, !centeredOnUser {
            centeredOnUser = true
            mapView.setRegion(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan), animated: false)
        }
        updateVenuesLocation(location)
        reloadActionRows()
    }

    func mapView(_: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        guard let annotation = annotation as? VenueAnnotation else { return nil }
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: Self.venueAnnotationIdentifier,
            for: annotation,
        )
        guard let marker = view as? MKMarkerAnnotationView else { return view }
        marker.markerTintColor = annotation.venue.iconColor
        marker.glyphImage = UIImage(systemName: annotation.venue.symbolName)
        marker.canShowCallout = false
        marker.titleVisibility = .hidden
        return marker
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        guard let annotation = annotation as? VenueAnnotation else { return }
        geocodeTask?.cancel()
        selection = .venue(annotation.venue)
        mapView.setCenter(annotation.venue.coordinate, animated: true)
        updatePin()
        updatePlacesButton()
        reloadActionRows()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
        guard userIsDraggingMap else { return }
        userIsDraggingMap = false
        let coordinate = mapView.centerCoordinate
        selection = .location(coordinate, address: nil)
        updatePin()
        reloadActionRows()
        reverseGeocode(coordinate)
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: Location access

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }

    // MARK: Search

    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != searchQuery else { return }
        searchQuery = query
        searchTask?.cancel()
        searchResults = nil
        tableView.reloadData()
        guard !query.isEmpty else { return }
        let coordinate = mapView.centerCoordinate
        // LocationSearchContainerNode: a second after typing stops, the addresses for the query and the venue bot's
        // places for it around the map's center.
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            async let foundPlacemarks = Self.placemarks(for: query, around: coordinate)
            let places = await venues(around: coordinate, query: query) ?? []
            let placemarks = await foundPlacemarks
            guard !Task.isCancelled, searchQuery == query else { return }
            searchResults = (placemarks, places)
            tableView.reloadData()
        }
    }

    private func configureMap() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.preferredConfiguration = mapMode.configuration
        mapView.showsCompass = false
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Self.venueAnnotationIdentifier,
        )
        let pan = UIPanGestureRecognizer(target: self, action: #selector(mapPanned(_:)))
        pan.delegate = self
        mapView.addGestureRecognizer(pan)

        pinView.translatesAutoresizingMaskIntoConstraints = false
        pinView.image = UIImage(
            systemName: "mappin.and.ellipse",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold),
        )
        pinView.tintColor = .systemRed
        pinView.isHidden = true
        pinView.isUserInteractionEnabled = false

        var userLocationConfiguration = UIButton.Configuration.filled()
        userLocationConfiguration.image = UIImage(systemName: "location.fill")
        userLocationConfiguration.baseBackgroundColor = .systemBackground
        userLocationConfiguration.baseForegroundColor = .systemBlue
        userLocationConfiguration.cornerStyle = .capsule
        userLocationButton.configuration = userLocationConfiguration
        userLocationButton.translatesAutoresizingMaskIntoConstraints = false
        userLocationButton.accessibilityLabel = L10n.telegram("Map.SendMyCurrentLocation")
        userLocationButton.addTarget(self, action: #selector(userLocationPressed), for: .touchUpInside)

        var placesConfiguration = UIButton.Configuration.filled()
        placesConfiguration.title = L10n.telegram("Map.PlacesInThisArea")
        placesConfiguration.baseBackgroundColor = .systemBackground
        placesConfiguration.baseForegroundColor = .systemBlue
        placesConfiguration.cornerStyle = .capsule
        placesButton.configuration = placesConfiguration
        placesButton.translatesAutoresizingMaskIntoConstraints = false
        placesButton.isHidden = true
        placesButton.addTarget(self, action: #selector(placesPressed), for: .touchUpInside)

        for button in [userLocationButton, placesButton] {
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.15
            button.layer.shadowRadius = 6
            button.layer.shadowOffset = CGSize(width: 0, height: 2)
        }
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.loadingCellIdentifier)
    }

    private func layoutViews() {
        view.addSubview(mapView)
        view.addSubview(pinView)
        view.addSubview(userLocationButton)
        view.addSubview(placesButton)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.4),
            pinView.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            // The ellipse under the pin marks the picked point at the map's center.
            pinView.bottomAnchor.constraint(equalTo: mapView.centerYAnchor, constant: 6),
            userLocationButton.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -12),
            userLocationButton.bottomAnchor.constraint(equalTo: mapView.bottomAnchor, constant: -12),
            userLocationButton.widthAnchor.constraint(equalToConstant: 44),
            userLocationButton.heightAnchor.constraint(equalToConstant: 44),
            placesButton.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            placesButton.topAnchor.constraint(equalTo: mapView.topAnchor, constant: 12),
            tableView.topAnchor.constraint(equalTo: mapView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func mapModeMenu() -> UIMenu {
        UIMenu(children: MapMode.allCases.map { mode in
            UIAction(title: L10n.telegram(mode.titleKey), state: mode == mapMode ? .on : .off) { [weak self] _ in
                self?.setMapMode(mode)
            }
        })
    }

    private func setMapMode(_ mode: MapMode) {
        guard mode != mapMode else { return }
        mapMode = mode
        mapView.preferredConfiguration = mode.configuration
        mapModeItem.menu = mapModeMenu()
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
            // Without the user's location the pin picks the place, as after dragging the map.
            if case .current = selection {
                let coordinate = mapView.centerCoordinate
                selection = .location(coordinate, address: nil)
                reverseGeocode(coordinate)
            }
            if nearbyVenues == nil { nearbyVenues = [] }
            updatePin()
            tableView.reloadData()
        }
    }

    @objc private func cancelPressed() {
        let onDismiss = onDismiss
        dismiss(animated: true) { onDismiss?() }
    }

    @objc private func mapPanned(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began else { return }
        // Telegram's beganInteractiveDragging: the pin lifts and the place becomes the dragged-to location.
        userIsDraggingMap = true
        searchingVenuesAround = false
        geocodeTask?.cancel()
        selection = .selecting
        for annotation in mapView.selectedAnnotations {
            mapView.deselectAnnotation(annotation, animated: true)
        }
        updatePin()
        updatePlacesButton()
        reloadActionRows()
    }

    @objc private func userLocationPressed() {
        guard !accessDenied else {
            presentAccessDenied()
            return
        }
        goToUserLocation()
    }

    /// Telegram's goToUserLocation: back to the user's location and the places around it.
    private func goToUserLocation() {
        geocodeTask?.cancel()
        areaTask?.cancel()
        selection = .current
        areaVenues = nil
        areaCoordinate = nil
        searchingVenuesAround = false
        for annotation in mapView.selectedAnnotations {
            mapView.deselectAnnotation(annotation, animated: false)
        }
        if let coordinate = userLocation?.coordinate {
            mapView.setRegion(MKCoordinateRegion(center: coordinate, span: Self.defaultSpan), animated: true)
        }
        updatePin()
        updatePlacesButton()
        updateVenueAnnotations()
        tableView.reloadData()
    }

    /// Telegram's requestPlacesAtSelectedLocation.
    @objc private func placesPressed() {
        guard case .location(let coordinate, _) = selection else { return }
        mapView.setCenter(coordinate, animated: true)
        searchingVenuesAround = true
        areaVenues = nil
        updatePlacesButton()
        tableView.reloadData()
        areaTask?.cancel()
        areaTask = Task { [weak self] in
            guard let self else { return }
            let found = await venues(around: coordinate)
            guard !Task.isCancelled else { return }
            areaVenues = found ?? []
            areaCoordinate = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            updatePlacesButton()
            updateVenueAnnotations()
            tableView.reloadData()
        }
    }

    private func loadNearbyVenues(around coordinate: CLLocationCoordinate2D) {
        nearbyTask?.cancel()
        nearbyTask = Task { [weak self] in
            guard let self else { return }
            let found = await venues(around: coordinate)
            guard !Task.isCancelled else { return }
            // Telegram lists no places when the bot doesn't answer.
            nearbyVenues = found ?? []
            updateVenueAnnotations()
            tableView.reloadData()
        }
    }

    /// Telegram's throttledUserLocation: places load for the first fix with an accuracy, then again once the user
    /// moves over 250 m or the fix gets better than 50 m.
    private func updateVenuesLocation(_ location: CLLocation) {
        guard location.horizontalAccuracy > 0 else { return }
        if let current = venuesLocation {
            guard location.distance(from: current) > 250
                || (location.horizontalAccuracy < 50 && location.horizontalAccuracy < current.horizontalAccuracy)
            else { return }
        }
        venuesLocation = location
        loadNearbyVenues(around: location.coordinate)
    }

    /// SearchBotsConfiguration.venueBotUsername: the bot named by venue_search_bot_username, else @foursquare,
    /// resolved once.
    private func venueSearchBot() async -> Int64? {
        if let venueSearchBotUserID { return venueSearchBotUserID }
        var username = "foursquare"
        if case .optionValueString(let option) = try? await client.getOption(name: "venue_search_bot_username"),
           !option.value.isEmpty
        {
            username = option.value
        }
        guard let chat = try? await client.send(TDNativeRequests.searchPublicChat(username: username)),
              case .chatTypePrivate(let bot) = chat.type
        else { return nil }
        venueSearchBotUserID = bot.userId
        return bot.userId
    }

    /// Telegram's nearbyVenues: an inline query to the venue search bot with the location, the search text or
    /// nothing as its query, and the venues among its results. Nil when the bot doesn't answer.
    private func venues(around coordinate: CLLocationCoordinate2D, query: String = "") async -> [LocationPickerVenue]? {
        guard let botUserID = await venueSearchBot() else { return nil }
        guard let found = try? await client.send(TDNativeRequests.getInlineQueryResults(
            botUserId: botUserID,
            chatId: chatID,
            userLocation: TDNativeLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                horizontalAccuracy: 0,
            ),
            query: query,
            offset: "",
        )) else { return nil }
        return found.results.compactMap { result -> LocationPickerVenue? in
            guard case .inlineQueryResultVenue(let venue) = result else { return nil }
            return LocationPickerVenue(venue: venue.venue)
        }
    }

    /// Telegram's goToCoordinate from search: the address becomes the picked location and the search closes.
    private func goToCoordinate(_ coordinate: CLLocationCoordinate2D) {
        telegramNavigationSearch.endTelegramNavigationSearch()
        searchQuery = ""
        searchTask?.cancel()
        searchResults = nil
        geocodeTask?.cancel()
        searchingVenuesAround = false
        selection = .location(coordinate, address: nil)
        for annotation in mapView.selectedAnnotations {
            mapView.deselectAnnotation(annotation, animated: false)
        }
        mapView.setCenter(coordinate, animated: true)
        updatePin()
        updatePlacesButton()
        updateVenueAnnotations()
        tableView.reloadData()
        reverseGeocode(coordinate)
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        geocodeTask = Task { [weak self] in
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let request = MKReverseGeocodingRequest(location: location) else { return }
            let items = try? await request.mapItems
            guard let self, !Task.isCancelled,
                  case .location(let current, nil) = selection,
                  current.latitude == coordinate.latitude,
                  current.longitude == coordinate.longitude
            else { return }
            let address = items?.first.flatMap(Self.address(of:)) ?? L10n.telegram("Map.Unknown")
            selection = .location(coordinate, address: address)
            updatePlacesButton()
            reloadActionRows()
        }
    }

    /// Telegram shows Places In This Area once a dragged-to location has its address, unless its places are already
    /// shown or were found within 300 m of it.
    private func updatePlacesButton() {
        var showsButton = false
        if case .location(let coordinate, let address) = selection, address != nil {
            if areaVenues == nil, !searchingVenuesAround {
                showsButton = true
            } else if let areaCoordinate {
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                showsButton = location.distance(from: areaCoordinate) > 300
            }
        }
        guard placesButton.isHidden == showsButton else { return }
        placesButton.isHidden = !showsButton
    }

    private func updatePin() {
        let showsPin: Bool
        let lifted: Bool
        switch selection {
        case .current, .venue:
            showsPin = false
            lifted = false
        case .selecting:
            showsPin = true
            lifted = true
        case .location:
            showsPin = true
            lifted = false
        }
        pinView.isHidden = !showsPin
        UIView.animate(withDuration: 0.2) {
            self.pinView.transform = lifted ? CGAffineTransform(translationX: 0, y: -10) : .identity
        }
    }

    private func updateVenueAnnotations() {
        mapView.removeAnnotations(mapView.annotations.filter { $0 is VenueAnnotation })
        let venues = (areaVenues != nil || searchingVenuesAround) ? areaVenues ?? [] : nearbyVenues ?? []
        mapView.addAnnotations(venues.map(VenueAnnotation.init(venue:)))
    }

    private func reloadActionRows() {
        guard !isSearching else { return }
        UIView.performWithoutAnimation {
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
        }
    }

    private func row(at indexPath: IndexPath) -> Row {
        let rows = indexPath.section == 0 ? actionRows : venueRows
        return rows.indices.contains(indexPath.row) ? rows[indexPath.row] : .loading
    }

    /// The first row's title and subtitle for the selected place (LocationPickerControllerNode entries).
    private func sendRowText() -> (String, String) {
        switch selection {
        case .current:
            let subtitle = userLocation.map {
                L10n.telegram("Map.AccurateTo", distanceFormatter.string(fromDistance: $0.horizontalAccuracy))
            } ?? L10n.telegram("Map.Locating")
            let title = pollSubtitle == nil ? "Map.SendMyCurrentLocation" : "Location.AddThisLocation"
            return (L10n.telegram(title), subtitle)
        case .selecting:
            return (L10n.telegram("Map.SendThisLocation"), L10n.telegram("Map.Locating"))
        case .location(_, let address):
            return (L10n.telegram("Map.SendThisLocation"), address ?? L10n.telegram("Map.Locating"))
        case .venue(let venue):
            return (L10n.telegram("Map.SendThisPlace"), venue.title)
        }
    }

    private func sendSelection() {
        switch selection {
        case .current:
            guard !accessDenied else {
                presentAccessDenied()
                return
            }
            guard let coordinate = userLocation?.coordinate else { return }
            finish(with: .inputMessageLocation(TDNativeInputMessageLocation(location: TDNativeLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                horizontalAccuracy: userAccuracy,
            ))))
        case .selecting:
            break
        case .location(let coordinate, _):
            finish(with: .inputMessageLocation(TDNativeInputMessageLocation(location: TDNativeLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                horizontalAccuracy: 0,
            ))))
        case .venue(let venue):
            finish(with: venue.content)
        }
    }

    /// Telegram's sendLiveLocation: the period from makeLiveLocationDurationContextController, then the user's
    /// location as a live location for it.
    private func shareLiveLocation(from sourceView: UIView?) {
        guard !accessDenied else {
            presentAccessDenied()
            return
        }
        guard userLocation != nil else { return }
        let description = (peerName.map { L10n.telegram("Map.LiveLocationPrivateNewDescription", $0) }
            ?? L10n.telegram("Map.LiveLocationGroupNewDescription"))
            .replacingOccurrences(of: "**", with: "")
        let sheet = UIAlertController(title: nil, message: description, preferredStyle: .actionSheet)
        for period in Self.livePeriods {
            sheet.addAction(UIAlertAction(title: Self.livePeriodTitle(period), style: .default) { [weak self] _ in
                self?.sendLiveLocation(period: period)
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView ?? tableView
            popover.sourceRect = (sourceView ?? tableView).bounds
        }
        present(sheet, animated: true)
    }

    private func sendLiveLocation(period: Int) {
        guard let coordinate = userLocation?.coordinate else { return }
        finish(with: .inputMessageLiveLocation(TDNativeInputMessageLiveLocation(location: TDNativeLiveLocation(
            location: TDNativeLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                horizontalAccuracy: userAccuracy,
            ),
            livePeriod: period,
            heading: 0,
            proximityAlertRadius: 0,
        ))))
    }

    private func finish(with content: InputMessageContent) {
        guard !didSend else { return }
        didSend = true
        let send = send
        let onDismiss = onDismiss
        dismiss(animated: true) {
            onDismiss?()
            send(content)
        }
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
