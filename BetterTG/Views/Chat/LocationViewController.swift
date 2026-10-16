// LocationViewController.swift

import Combine
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
    /// The message's chat and sender, which the proximity alert depends on; nil for a location from rich content.
    let chatID: Int64?
    let sender: MessageSender?

    init?(message: Message) {
        self.chatID = message.chatId
        self.sender = message.senderId
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
        self.chatID = nil
        self.sender = nil
    }

    /// A place outside a venue message, such as a poll's or an answer's.
    init(venue: TDNativeVenue) {
        let place = LocationPickerVenue(venue: venue)
        self.coordinate = place.coordinate
        self.venue = place
        self.liveMessage = nil
        self.chatID = nil
        self.sender = nil
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

// MARK: - LocationSender

/// A live location's sender as the viewer shows them: Telegram's displayTitle and avatar.
private struct LocationSender {
    let title: String
    let file: File?
    let minithumbnail: Minithumbnail?
    let placeholder: TelegramAvatarPlaceholder

    /// The sender as one number: users are positive, and the chats that send messages negative.
    static func key(of sender: MessageSender) -> Int64 {
        switch sender {
        case .messageSenderChat(let chat): chat.chatId
        case .messageSenderUser(let user): user.userId
        }
    }

    @MainActor static func load(_ sender: MessageSender, client: TDLibClient) async -> Self? {
        switch sender {
        case .messageSenderChat(let value):
            guard let chat = try? await client.getChat(chatId: value.chatId) else { return nil }
            return Self(
                title: chat.title,
                file: chat.photo?.small,
                minithumbnail: chat.photo?.minithumbnail,
                placeholder: TelegramAvatarPlaceholder(
                    peerID: chat.id,
                    accentColorID: chat.accentColorId,
                    upgradedGiftColors: chat.upgradedGiftColors,
                    letters: chat.title.telegramAvatarFirstLetter.map { [$0] } ?? [],
                    isDeleted: false,
                ),
            )
        case .messageSenderUser(let value):
            guard let user = try? await client.getUser(userId: value.userId) else { return nil }
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            return Self(
                title: name.isEmpty ? L10n.telegram("User.DeletedAccount") : name,
                file: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
                placeholder: user.telegramAvatarPlaceholder,
            )
        }
    }
}

// MARK: - LiveLocationRing

/// The state of a live location's remaining-time ring.
private struct LiveLocationRing {
    let deadline: Foundation.Date
    let period: TimeInterval
    let isIndefinite: Bool
}

// MARK: - LiveLocationAnnotation

/// LocationPinAnnotation for a live location message: the sender's pin at their latest location.
private final class LiveLocationAnnotation: MKPointAnnotation {
    let messageID: Int64
    let senderKey: Int64

    init(messageID: Int64, senderKey: Int64) {
        self.messageID = messageID
        self.senderKey = senderKey
        super.init()
    }
}

// MARK: - LiveLocationAnnotationView

/// LocationPinAnnotationView for a person: their avatar in a small round badge, raised into a pin while selected.
private final class LiveLocationAnnotationView: MKAnnotationView {
    private static let shadowInset: CGFloat = 3
    private static let pinRadius: CGFloat = 31
    private static let pinTail: CGFloat = 12
    private static let badgeDiameter: CGFloat = 40
    private static let pinImage = makePinImage()
    private static let badgeImage = makeBadgeImage()

    private let backgroundView = UIImageView()
    private let avatarView = ProfileAvatarView()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        displayPriority = .required
        collisionMode = .circle
        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        addSubview(backgroundView)
        addSubview(avatarView)
        applyAppearance(selected: false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            applyAppearance(selected: selected)
            return
        }
        UIView.animate(withDuration: 0.2) {
            self.applyAppearance(selected: selected)
            self.layoutIfNeeded()
        }
    }

    /// LocationPinAnnotationView's pin: a white circle around a 55 point avatar, pointing at the location.
    private static func makePinImage() -> UIImage {
        let size = CGSize(width: (pinRadius + shadowInset) * 2, height: (pinRadius + shadowInset) * 2 + pinTail)
        return UIGraphicsImageRenderer(size: size).image { context in
            let center = CGPoint(x: size.width / 2, y: shadowInset + pinRadius)
            let path = UIBezierPath(
                arcCenter: center,
                radius: pinRadius,
                startAngle: CGFloat.pi / 2 + 0.35,
                endAngle: CGFloat.pi / 2 - 0.35,
                clockwise: true,
            )
            path.addLine(to: CGPoint(x: center.x, y: size.height - shadowInset))
            path.close()
            context.cgContext.setShadow(offset: .zero, blur: 3, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            UIColor.white.setFill()
            path.fill()
        }
    }

    /// LocationPinAnnotationView's small node: a white badge around the avatar.
    private static func makeBadgeImage() -> UIImage {
        let side = badgeDiameter + shadowInset * 2
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setShadow(offset: .zero, blur: 4, color: UIColor.black.withAlphaComponent(0.5).cgColor)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: shadowInset, dy: shadowInset)).fill()
        }
    }

    func configure(sender: LocationSender?, client: TDLibClient) {
        guard let sender else { return }
        avatarView.configure(
            file: sender.file,
            minithumbnail: sender.minithumbnail,
            placeholder: sender.placeholder,
            client: client,
        )
    }

    /// The pin's tip, or the badge's center, sits on the location.
    private func applyAppearance(selected: Bool) {
        let image = selected ? Self.pinImage : Self.badgeImage
        bounds = CGRect(origin: .zero, size: image.size)
        backgroundView.image = image
        backgroundView.frame = bounds
        let avatarSize: CGFloat = selected ? 55 : 35
        let avatarCenter = CGPoint(
            x: image.size.width / 2,
            y: selected ? Self.shadowInset + Self.pinRadius : image.size.height / 2,
        )
        avatarView.frame = CGRect(
            x: avatarCenter.x - avatarSize / 2,
            y: avatarCenter.y - avatarSize / 2,
            width: avatarSize,
            height: avatarSize,
        )
        centerOffset = selected ? CGPoint(x: 0, y: -(image.size.height / 2 - Self.shadowInset)) : .zero
    }
}

// MARK: - LocationLiveCell

/// LocationLiveListItem: the sender's avatar, their name, when their location was updated and how far away it is,
/// the ring of the time left, and the directions buttons.
private final class LocationLiveCell: UITableViewCell {
    static let reuseIdentifier = "LocationLiveCell"

    var onDirections: ((LocationDirections) -> Void)?

    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let timerView = LiveLocationTimerView()
    private let directionsView = LocationDirectionsView(buttonHeight: 36, fontSize: 14, fillsWidth: false)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        timerView.translatesAutoresizingMaskIntoConstraints = false
        directionsView.translatesAutoresizingMaskIntoConstraints = false
        directionsView.onDirections = { [weak self] directions in self?.onDirections?(directions) }
        for subview in [avatarView, titleLabel, subtitleLabel, timerView, directionsView] {
            contentView.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timerView.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timerView.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            timerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            timerView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            timerView.widthAnchor.constraint(equalToConstant: 24),
            timerView.heightAnchor.constraint(equalToConstant: 24),
            directionsView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            directionsView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            directionsView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            directionsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        onDirections = nil
    }

    /// - Parameter ring: Nil once the period has ended, which hides the ring.
    func configure(
        sender: LocationSender?,
        subtitle: String,
        ring: LiveLocationRing?,
        driving: LocationTravelTime,
        walking: LocationTravelTime,
        client: TDLibClient,
    ) {
        if let sender {
            avatarView.configure(
                file: sender.file,
                minithumbnail: sender.minithumbnail,
                placeholder: sender.placeholder,
                client: client,
            )
        }
        titleLabel.text = sender?.title ?? " "
        subtitleLabel.text = subtitle
        timerView.isHidden = ring == nil
        if let ring {
            timerView.configure(deadline: ring.deadline, period: ring.period, isIndefinite: ring.isIndefinite)
        }
        directionsView.configure(driving: driving, walking: walking)
    }
}

// MARK: - ProximityCircleRenderer

/// LocationMapNode.ProximityCircleRenderer: the proximity alert's dashed circle around the user, with a bell cut into
/// its bottom edge.
private final class ProximityCircleRenderer: MKCircleRenderer {
    // MARK: Private

    /// Telegram's Location/ProximityIcon, a 24-point bell.
    private static let iconSize: CGFloat = 24

    private let icon: CGImage?

    init(circle: MKCircle, color: UIColor) {
        let size = CGSize(width: ProximityCircleRenderer.iconSize, height: ProximityCircleRenderer.iconSize)
        let symbol = UIImage(
            systemName: "bell",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular),
        )?.withTintColor(color, renderingMode: .alwaysOriginal)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        self.icon = symbol.flatMap { symbol in
            UIGraphicsImageRenderer(size: size, format: format)
                .image { _ in
                    symbol.draw(in: CGRect(
                        x: (size.width - symbol.size.width) / 2,
                        y: (size.height - symbol.size.height) / 2,
                        width: symbol.size.width,
                        height: symbol.size.height,
                    ))
                }
                .cgImage
        }
        super.init(circle: circle)
        fillColor = .clear
        strokeColor = color
        lineWidth = 0.75
        lineDashPattern = [5, 4]
    }

    // MARK: Internal

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        super.draw(mapRect, zoomScale: zoomScale, in: context)
        guard let icon else { return }
        context.saveGState()
        let boundingRect = circle.boundingMapRect
        let drawingPoint = point(for: MKMapPoint(x: boundingRect.midX, y: boundingRect.maxY))
        let side = floor(Self.iconSize / zoomScale * contentScaleFactor * 0.75)
        context.translateBy(x: drawingPoint.x, y: drawingPoint.y)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -drawingPoint.x, y: -drawingPoint.y)
        let imageRect = CGRect(
            x: floor(drawingPoint.x - side / 2),
            y: floor(drawingPoint.y - side / 2),
            width: side,
            height: side,
        )
        context.clear(imageRect)
        context.draw(icon, in: imageRect)
        context.restoreGState()
    }
}

// MARK: - LocationTipView

/// Telegram's TooltipScreen by the proximity alert button: a dark bubble whose arrow points right at it.
private final class LocationTipView: UIView {
    // MARK: Private

    private static let arrowSize = CGSize(width: 7, height: 14)

    private let shapeLayer = CAShapeLayer()
    private let label = UILabel()

    init(text: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        shapeLayer.fillColor = UIColor(white: 0.1, alpha: 0.9).cgColor
        layer.addSublayer(shapeLayer)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(12 + Self.arrowSize.width)),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func layoutSubviews() {
        super.layoutSubviews()
        let bubble = CGRect(x: 0, y: 0, width: max(0, bounds.width - Self.arrowSize.width), height: bounds.height)
        let path = UIBezierPath(roundedRect: bubble, cornerRadius: 10)
        path.move(to: CGPoint(x: bubble.maxX, y: bounds.midY - Self.arrowSize.height / 2))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.midY))
        path.addLine(to: CGPoint(x: bubble.maxX, y: bounds.midY + Self.arrowSize.height / 2))
        path.close()
        shapeLayer.frame = bounds
        shapeLayer.path = path.cgPath
    }
}

// MARK: - LocationViewController

/// Telegram's LocationViewController. For a location or a venue: the map centered on the place's pin, and under it
/// the place's title, its address and distance, and directions by car and on foot with their travel times; Share
/// opens the place in another app or shares a link to it. For a live location: every live location shared in the
/// chat, as avatar pins and as rows with when each was updated, its distance, the time left and directions, with the
/// actions that share, extend or stop the account's own, and Show All. The map buttons switch the map type and follow
/// the user, and where Telegram offers it the bell sets or cancels a proximity alert on the account's own live
/// location.
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

    /// LocationViewEntry.
    private enum Row: Equatable {
        case info
        /// Share My Live Location for...
        case shareLiveLocation
        /// Sharing Location... with the ring of the time left; tapping it adds time.
        case extendLiveLocation
        /// Stop Sharing Location, with the ring when it is the only action.
        case stopLiveLocation(showsRing: Bool)
        case liveLocation(messageID: Int64)
    }

    /// Travel times to a live location and when they were asked for.
    private struct LiveTravelTimes {
        let date: Foundation.Date
        let driving: LocationTravelTime
        let walking: LocationTravelTime
    }

    /// The message's own pin, kept selected as Telegram's forcedSelection.
    private final class SubjectAnnotation: MKPointAnnotation {}

    /// What Telegram's proximity alert button depends on about the chat.
    private struct ProximityChat {
        /// A private chat with a user, Telegram's CloudUser namespace.
        let isUser: Bool
        /// The message is a channel's post: its author is a broadcast channel.
        let isBroadcastPost: Bool
        let title: String
    }

    private static let subjectAnnotationIdentifier = "LocationSubject"
    private static let liveAnnotationIdentifier = "LocationLive"
    private static let userAnnotationIdentifier = "LocationUser"
    private static let actionCellIdentifier = "LocationActionCell"
    /// Telegram's LocationMapNode.viewMapSpan.
    private static let viewSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
    /// Telegram's LocationMapNode.defaultMapSpan.
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.016, longitudeDelta: 0.016)
    /// The list never covers more of the screen than this.
    private static let maximumListFraction: CGFloat = 0.6
    /// Telegram redraws the live locations' times every 10 seconds.
    private static let liveRefreshInterval: TimeInterval = 10
    /// Telegram asks for a live location's travel times again once they are a minute old.
    private static let travelTimeLifetime: TimeInterval = 60
    /// TDLib's limit for a location's horizontal accuracy.
    private static let maximumAccuracy: CLLocationAccuracy = 1500
    /// LocationActionListItem's live location colors.
    private static let startColor = UIColor(rgb: 0x6CC138)
    private static let stopColor = UIColor(rgb: 0xFF6464)
    /// LocationMapNode's proximity dim: a clear circle of 260 points.
    private static let proximityHoleDiameter: CGFloat = 260
    /// LocationMapNode's proximity circle.
    private static let proximityCircleColor = UIColor(rgb: 0xC3BAAF)
    /// ApplicationSpecificNotice's locationProximityAlertTip: the hint shows on three openings, and setting up an alert
    /// retires it.
    private static let proximityTipCountKey = "Location.ProximityAlertTipCount"
    /// The live location period Telegram shares for an alert set without one.
    private static let proximityLivePeriod = 30 * 60

    private let subject: LocationViewSubject
    private let client: TDLibClient
    private let source: TdUpdateSource?
    private let canShareLiveLocation: Bool
    private let peerName: String?
    private let showsAllLiveLocations: Bool
    private let sendLiveLocation: ((InputMessageContent) -> Void)?
    private let locationManager = CLLocationManager()
    private let mapView = MKMapView()
    private let mapModeButton = UIButton(type: .system)
    private let trackingButton = UIButton(type: .system)
    private let proximityButton = UIButton(type: .system)
    private let proximityDimView = UIImageView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let subjectAnnotation = SubjectAnnotation()
    private let distanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .full
        return formatter
    }()

    private let shortDistanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    private var tableHeightConstraint: NSLayoutConstraint?
    private var contentSizeObservation: NSKeyValueObservation?
    private var mapMode = MapMode.map
    private var rows: [[Row]] = [[.info]]
    private var userLocation: CLLocation?
    private var accessDenied = false
    /// The venue's address, or the reverse geocoded one; nil while it is looked up.
    private var address: String?
    private var drivingTime = LocationTravelTime.calculating
    private var walkingTime = LocationTravelTime.calculating
    private var geocodeTask: Task<Void, Never>?
    private var travelTimeTask: Task<Void, Never>?
    private var iconCache = [String: UIImage]()
    private var cancellables = Set<AnyCancellable>()
    /// Telegram's live locations of the chat (topPeerActiveLiveLocationMessages), the opened message first.
    private var liveMessages = [Message]()
    /// The account's own live locations in the chat that LiveLocationManager is sharing.
    private var ownBroadcasts = [LiveLocationBroadcast]()
    private var senders = [Int64: LocationSender]()
    private var loadingSenders = Set<Int64>()
    private var liveAnnotations = [Int64: LiveLocationAnnotation]()
    private var liveTravelTimes = [Int64: LiveTravelTimes]()
    private var liveTravelTasks = [Int64: Task<Void, Never>]()
    private var refreshingMessageIDs = Set<Int64>()
    private var staleMessageIDs = Set<Int64>()
    private var liveLoadTask: Task<Void, Never>?
    private var liveTimer: Timer?
    /// Whether the user's location shows the account's avatar for its own live location.
    private var showsOwnAnnotation = false
    private var didShowAllLiveLocations = false
    private var proximityChat: ProximityChat?
    private var proximityChatTask: Task<Void, Never>?
    /// Telegram's proximityNotification: nil hides the bell, false offers an alert, and true cancels the one set.
    private var proximityNotification: Bool?
    /// The own alert's radius drawn around the user, Telegram's activeProximityRadius.
    private var activeProximityRadius: Int?
    private var proximityCircle: MKCircle?
    /// Telegram's updatingProximityRadius and cancellingProximityRadius: the alert as set while its edit is on the way.
    private var updatingProximityRadius: Int?
    private var cancellingProximityRadius = false
    /// The radius being picked, Telegram's proximityIndicatorRadius.
    private var proximityIndicatorRadius: Int?
    private var proximityDimHole: CGRect?
    private var displayedProximityTip = false
    private weak var proximityTipView: LocationTipView?
    private var proximityTipTask: Task<Void, Never>?

    private var isLiveView: Bool {
        subject.liveMessage != nil
    }

    private var chatID: Int64 {
        subject.chatID ?? 0
    }

    private var ownBroadcastIDs: Set<Int64> {
        Set(ownBroadcasts.map(\.messageID))
    }

    /// Telegram's activeOwnLiveLocation: the account's own live location here while it is shared.
    private var ownLiveMessage: Message? {
        liveMessages.first { $0.isOutgoing && ownBroadcastIDs.contains($0.id) }
    }

    /// Telegram's ownMessageId for the proximity alert: the account's own live location shared in the chat, also
    /// when the chat's live locations aren't listed.
    private var ownProximityMessageID: Int64? {
        ownLiveMessage?.id ?? ownBroadcasts.first?.messageID
    }

    /// - Parameters:
    ///   - client: The client of the message's chat.
    ///   - source: That client's updates keep the live locations current.
    ///   - canShareLiveLocation: Whether the account can share its live location in the chat.
    ///   - peerName: The other user's name in a private chat, for the live location description.
    ///   - showsAllLiveLocations: Telegram's showAll for the viewer opened from the live location panel.
    ///   - sendLiveLocation: Sends the account's live location to the chat.
    init(
        subject: LocationViewSubject,
        client: TDLibClient,
        source: TdUpdateSource?,
        canShareLiveLocation: Bool = false,
        peerName: String? = nil,
        showsAllLiveLocations: Bool = false,
        sendLiveLocation: ((InputMessageContent) -> Void)? = nil,
    ) {
        self.subject = subject
        self.client = client
        self.source = source
        self.canShareLiveLocation = canShareLiveLocation
        self.peerName = peerName
        self.showsAllLiveLocations = showsAllLiveLocations
        self.sendLiveLocation = sendLiveLocation
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        geocodeTask?.cancel()
        travelTimeTask?.cancel()
        liveLoadTask?.cancel()
        proximityChatTask?.cancel()
        proximityTipTask?.cancel()
        liveTimer?.invalidate()
        for task in liveTravelTasks.values {
            task.cancel()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Map.LocationTitle")
        view.backgroundColor = .systemGroupedBackground
        // The classic chrome draws no system items, so Close is Telegram's text button.
        navigationItem.leftBarButtonItem = UIBarButtonItem(primaryAction: UIAction(
            title: L10n.telegram("Common.Close"),
        ) { [weak self] _ in self?.dismiss(animated: true) })
        if !isLiveView {
            let shareItem = UIBarButtonItem()
            shareItem.primaryAction = UIAction(image: UIImage(systemName: "square.and.arrow.up")) {
                [weak self, weak shareItem] _ in
                guard let shareItem else { return }
                self?.share(from: shareItem)
            }
            shareItem.accessibilityLabel = L10n.telegram("Conversation.ContextMenuShare")
            navigationItem.rightBarButtonItem = shareItem
        }
        configureMap()
        configureTable()
        layoutViews()
        locationManager.delegate = self
        authorizationChanged()
        if isLiveView {
            startLiveLocations()
        } else {
            loadAddress()
        }
        if subject.chatID != nil {
            observeOwnBroadcasts()
            loadProximityChat()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableHeight()
        if proximityIndicatorRadius != nil {
            updateProximityDim()
        }
    }

    /// PeerLiveLocationsContext's filter: a live location whose period hasn't ended, or one shared until stopped.
    private static func isActive(_ message: Message) -> Bool {
        liveRing(of: message) != nil
    }

    /// The remaining-time ring of a live location, nil once its period has ended.
    private static func liveRing(of message: Message) -> LiveLocationRing? {
        guard case .messageLiveLocation(let live) = message.content else { return nil }
        let period = live.location.livePeriod
        let isIndefinite = period == LiveLocationManager.indefinitePeriod
        let deadline = message.date + period
        guard isIndefinite || deadline > Int(Foundation.Date().timeIntervalSince1970) else { return nil }
        return LiveLocationRing(
            deadline: Foundation.Date(timeIntervalSince1970: TimeInterval(deadline)),
            period: TimeInterval(period),
            isIndefinite: isIndefinite,
        )
    }

    private static func coordinate(of message: Message) -> CLLocationCoordinate2D? {
        guard case .messageLiveLocation(let live) = message.content else { return nil }
        return CLLocationCoordinate2D(
            latitude: live.location.location.latitude,
            longitude: live.location.location.longitude,
        )
    }

    /// The EditedMessageAttribute's date, else the message's.
    private static func updateDate(of message: Message) -> Foundation.Date {
        Foundation.Date(timeIntervalSince1970: TimeInterval(message.editDate > 0 ? message.editDate : message.date))
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
        let row = rows[indexPath.section][indexPath.row]
        switch row {
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
            let coordinate = subject.coordinate
            let venue = subject.venue
            infoCell.onDirections = { [weak self, weak infoCell] directions in
                self?.requestDirections(
                    directions,
                    coordinate: coordinate,
                    venue: venue,
                    name: nil,
                    sourceView: infoCell,
                )
            }
            return infoCell
        case .extendLiveLocation, .shareLiveLocation, .stopLiveLocation:
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.actionCellIdentifier, for: indexPath)
            configureAction(cell, row: row)
            return cell
        case .liveLocation(let messageID):
            let cell = tableView.dequeueReusableCell(withIdentifier: LocationLiveCell.reuseIdentifier, for: indexPath)
            guard let liveCell = cell as? LocationLiveCell,
                  let message = liveMessages.first(where: { $0.id == messageID }) else { return cell }
            configureLive(liveCell, message: message)
            return liveCell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.section][indexPath.row] {
        case .info:
            goToCoordinate(subject.coordinate)
        case .shareLiveLocation:
            presentLivePeriods(extend: false, sourceView: tableView.cellForRow(at: indexPath))
        case .extendLiveLocation:
            presentLivePeriods(extend: true, sourceView: tableView.cellForRow(at: indexPath))
        case .stopLiveLocation:
            stopLiveLocation()
        case .liveLocation(let messageID):
            guard let message = liveMessages.first(where: { $0.id == messageID }),
                  let coordinate = Self.coordinate(of: message) else { return }
            goToCoordinate(coordinate)
        }
    }

    // Map

    func mapView(_: MKMapView, didUpdate mapUserLocation: MKUserLocation) {
        guard let location = mapUserLocation.location else { return }
        let isFirstLocation = userLocation == nil
        userLocation = location
        if isFirstLocation {
            if isLiveView {
                updateLiveTravelTimes()
            } else {
                calculateTravelTimes()
            }
        }
        updateProximityCircle()
        reloadRows()
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            // Telegram's userLocationAnnotation: the account's avatar while it shares its live location here.
            guard showsOwnAnnotation, let own = ownLiveMessage else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.userAnnotationIdentifier,
                for: annotation,
            )
            (view as? LiveLocationAnnotationView)?.configure(
                sender: senders[LocationSender.key(of: own.senderId)],
                client: client,
            )
            return view
        }
        if let live = annotation as? LiveLocationAnnotation {
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.liveAnnotationIdentifier,
                for: annotation,
            )
            (view as? LiveLocationAnnotationView)?.configure(sender: senders[live.senderKey], client: client)
            return view
        }
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

    func mapView(_: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
        return ProximityCircleRenderer(circle: circle, color: Self.proximityCircleColor)
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
        mapView.register(
            LiveLocationAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Self.liveAnnotationIdentifier,
        )
        mapView.register(
            LiveLocationAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Self.userAnnotationIdentifier,
        )
        mapView.setRegion(MKCoordinateRegion(center: subject.coordinate, span: Self.viewSpan), animated: false)
        if !isLiveView {
            subjectAnnotation.coordinate = subject.coordinate
            subjectAnnotation.title = subject.venue?.title
            mapView.addAnnotation(subjectAnnotation)
        }

        // LocationMapHeaderNode's options: the map type, following the user's location, and the proximity alert.
        for button in [mapModeButton, trackingButton, proximityButton] {
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
        // LocationMapHeaderNode's notification button, with the mute icon while an alert is set.
        proximityButton.configuration?.image = UIImage(systemName: "bell.and.waves.left.and.right")
        proximityButton.addTarget(self, action: #selector(proximityPressed), for: .touchUpInside)
        proximityButton.accessibilityLabel = L10n.telegram("Location.ProximityNotification.Title")
        proximityButton.isHidden = true
        proximityDimView.translatesAutoresizingMaskIntoConstraints = false
        proximityDimView.isUserInteractionEnabled = false
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(LocationInfoCell.self, forCellReuseIdentifier: LocationInfoCell.reuseIdentifier)
        tableView.register(LocationLiveCell.self, forCellReuseIdentifier: LocationLiveCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.actionCellIdentifier)
        contentSizeObservation = tableView.observe(\.contentSize) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateTableHeight() }
        }
    }

    private func layoutViews() {
        view.addSubview(mapView)
        view.addSubview(proximityDimView)
        view.addSubview(mapModeButton)
        view.addSubview(trackingButton)
        view.addSubview(proximityButton)
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
            proximityButton.topAnchor.constraint(equalTo: trackingButton.bottomAnchor, constant: 8),
            proximityButton.trailingAnchor.constraint(equalTo: mapModeButton.trailingAnchor),
            proximityButton.widthAnchor.constraint(equalToConstant: 44),
            proximityButton.heightAnchor.constraint(equalToConstant: 44),
            proximityDimView.topAnchor.constraint(equalTo: mapView.topAnchor),
            proximityDimView.leadingAnchor.constraint(equalTo: mapView.leadingAnchor),
            proximityDimView.trailingAnchor.constraint(equalTo: mapView.trailingAnchor),
            proximityDimView.bottomAnchor.constraint(equalTo: mapView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableHeight,
        ])
    }

    /// The list sits under the map at its content's height, and scrolls once it would cover most of the screen. It
    /// makes room for the map while a proximity alert's radius is picked.
    private func updateTableHeight() {
        guard let tableHeightConstraint else { return }
        let insets = tableView.adjustedContentInset
        let maximumHeight = view.bounds.height * Self.maximumListFraction
        let height =
            proximityIndicatorRadius != nil
                ? 0
                : min(tableView.contentSize.height + insets.top + insets.bottom, maximumHeight)
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
            // Without the user's location MapKit has no travel times, and the rows offer Get Directions.
            if drivingTime == .calculating || walkingTime == .calculating {
                travelTimeTask?.cancel()
                drivingTime = .unknown
                walkingTime = .unknown
            }
            reloadRows()
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
            reloadRows()
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
            reloadRows()
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

    /// LocationViewControllerNode's entries: the info row for a location or a venue; for a live location the actions
    /// for the account's own, then everyone else's live locations.
    private func makeRows() -> [[Row]] {
        guard isLiveView else { return [[.info]] }
        var actions = [Row]()
        let own = ownLiveMessage
        if let own, case .messageLiveLocation(let live) = own.content {
            actions =
                if live.location.livePeriod == LiveLocationManager.indefinitePeriod {
                    [.stopLiveLocation(showsRing: true)]
                } else {
                    [.extendLiveLocation, .stopLiveLocation(showsRing: false)]
                }
        } else if canShareLiveLocation, sendLiveLocation != nil {
            actions = [.shareLiveLocation]
        }
        let sharers = liveMessages.filter { $0.id != own?.id }.map { Row.liveLocation(messageID: $0.id) }
        return [actions, sharers].filter { !$0.isEmpty }
    }

    /// A change of the rows reloads the list; otherwise the visible rows show the latest times and distances.
    private func reloadRows() {
        guard isViewLoaded else { return }
        let newRows = makeRows()
        guard newRows == rows else {
            rows = newRows
            tableView.reloadData()
            return
        }
        let visible = tableView.indexPathsForVisibleRows ?? []
        guard !visible.isEmpty else { return }
        tableView.reconfigureRows(at: visible)
    }

    /// LocationActionListItem: Share My Live Location; or Sharing Location... with the ring of the time left, and Stop
    /// Sharing Location with when the location was updated.
    private func configureAction(_ cell: UITableViewCell, row: Row) {
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.textProperties.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        configuration.secondaryTextProperties.color = .secondaryLabel
        configuration.imageProperties.maximumSize = CGSize(width: 40, height: 40)
        configuration.imageProperties.reservedLayoutSize = CGSize(width: 40, height: 40)
        var showsRing = false
        switch row {
        case .shareLiveLocation:
            configuration.text = L10n.telegram("Map.ShareLiveLocation")
            configuration.secondaryText = L10n.telegram("Map.ShareLiveLocationHelp")
            configuration.textProperties.color = .tintColor
            configuration.image = icon(symbol: "dot.radiowaves.left.and.right", color: Self.startColor)
        case .extendLiveLocation:
            configuration.text = L10n.telegram("Map.SharingLocation")
            configuration.secondaryText = L10n.telegram("Map.TapToAddTime")
            configuration.image = icon(symbol: "location.fill", color: Self.startColor, addsPlus: true)
            showsRing = true
        case .stopLiveLocation(let ring):
            configuration.text = L10n.telegram("Map.StopLiveLocation")
            configuration.secondaryText = ownLiveMessage
                .map { LiveLocationUpdateText.string(since: Self.updateDate(of: $0)) }
            configuration.image = icon(symbol: "location.slash.fill", color: Self.stopColor)
            showsRing = ring
        case .info, .liveLocation:
            break
        }
        cell.contentConfiguration = configuration
        guard showsRing, let own = ownLiveMessage, let ring = Self.liveRing(of: own) else {
            cell.accessoryView = nil
            return
        }
        let timerView = cell.accessoryView as? LiveLocationTimerView
            ?? LiveLocationTimerView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        timerView.configure(deadline: ring.deadline, period: ring.period, isIndefinite: ring.isIndefinite)
        cell.accessoryView = timerView
    }

    /// LocationLiveListItem's subtitle: when the location was updated, and how far away it is.
    private func configureLive(_ cell: LocationLiveCell, message: Message) {
        let coordinate = Self.coordinate(of: message)
        var subtitle = LiveLocationUpdateText.string(since: Self.updateDate(of: message))
        if let userLocation, let coordinate {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: userLocation)
            subtitle += " • " + L10n.telegram("Map.DistanceAway", shortDistance(distance))
        }
        let sender = senders[LocationSender.key(of: message.senderId)]
        let times = travelTimes(for: message)
        cell.configure(
            sender: sender,
            subtitle: subtitle,
            ring: Self.liveRing(of: message),
            driving: times.driving,
            walking: times.walking,
            client: client,
        )
        cell.onDirections = { [weak self, weak cell] directions in
            guard let self, let coordinate else { return }
            requestDirections(directions, coordinate: coordinate, venue: nil, name: sender?.title, sourceView: cell)
        }
    }

    /// Telegram's shortStringForDistance.
    private func shortDistance(_ distance: CLLocationDistance) -> String {
        let result = shortDistanceFormatter.string(fromDistance: Double(max(1, Int(distance))))
        return result.hasPrefix("0 ") ? result.replacingOccurrences(of: "0 ", with: "1 ") : result
    }

    /// Travel times are only asked for others' live locations; without the user's location the row offers Get
    /// Directions.
    private func travelTimes(for message: Message) -> (driving: LocationTravelTime, walking: LocationTravelTime) {
        guard !accessDenied, !message.isOutgoing else { return (.unknown, .unknown) }
        guard let times = liveTravelTimes[message.id] else { return (.calculating, .calculating) }
        return (times.driving, times.walking)
    }

    // Live locations

    /// Telegram's topPeerActiveLiveLocationMessages for the chat: TDLib's recent locations of its members, kept
    /// current by the messages' updates, with the account's own from LiveLocationManager.
    private func startLiveLocations() {
        guard let message = subject.liveMessage else { return }
        liveMessages = [message]
        observeLiveLocations()
        let timer = Timer(timeInterval: Self.liveRefreshInterval, repeats: true) { [weak self] _ in
            // The timer runs on the main run loop.
            MainActor.assumeIsolated { self?.liveTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
        liveLocationsChanged()
        let client = client
        let chatID = chatID
        liveLoadTask = Task { [weak self] in
            let found = try? await client.searchChatRecentLocationMessages(chatId: chatID, limit: 100)
            guard let self, !Task.isCancelled, let found else { return }
            for message in found.messages {
                merge(message)
            }
            liveLocationsChanged()
        }
    }

    private func observeLiveLocations() {
        nc.scopedPublisher(&cancellables, for: .updateMessageContent) { [weak self] event in
            guard let self, event.source == source, event.value.chatId == chatID,
                  liveMessages.contains(where: { $0.id == event.value.messageId }) else { return }
            refreshMessage(event.value.messageId)
        }
        nc.scopedPublisher(&cancellables, for: .updateMessageEdited) { [weak self] event in
            guard let self, event.source == source, event.value.chatId == chatID,
                  liveMessages.contains(where: { $0.id == event.value.messageId }) else { return }
            refreshMessage(event.value.messageId)
        }
        nc.scopedPublisher(&cancellables, for: .updateNewMessage) { [weak self] event in
            let message = event.value.message
            guard let self, event.source == source, message.chatId == chatID, message.sendingState == nil,
                  case .messageLiveLocation = message.content else { return }
            if merge(message) {
                liveLocationsChanged()
            }
        }
        nc.scopedPublisher(&cancellables, for: .updateDeleteMessages) { [weak self] event in
            guard let self, event.source == source, event.value.chatId == chatID,
                  event.value.isPermanent else { return }
            let deleted = Set(event.value.messageIds)
            let count = liveMessages.count
            liveMessages.removeAll { deleted.contains($0.id) }
            if liveMessages.count != count {
                liveLocationsChanged()
            }
        }
    }

    /// The account's own live locations here, for the actions and the proximity alert, whether or not the chat's live
    /// locations are listed.
    private func observeOwnBroadcasts() {
        LiveLocationManager.shared
            .$broadcasts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] broadcasts in self?.broadcastsChanged(broadcasts) }
            .store(in: &cancellables)
    }

    /// LiveLocationManager's broadcasts tell which live location here is the account's own and still shared, and its
    /// proximity alert.
    private func broadcastsChanged(_ broadcasts: [LiveLocationBroadcast]) {
        let own = broadcasts.filter { $0.source == source && $0.chatID == chatID }
        guard own != ownBroadcasts else { return }
        let previousIDs = ownBroadcastIDs
        ownBroadcasts = own
        let ids = ownBroadcastIDs
        guard isLiveView, ids != previousIDs else {
            updateProximityState()
            return
        }
        for id in ids where !liveMessages.contains(where: { $0.id == id }) {
            refreshMessage(id)
        }
        liveLocationsChanged()
    }

    /// The message's latest state from TDLib after an edit; another update meanwhile asks again.
    private func refreshMessage(_ messageID: Int64) {
        guard !refreshingMessageIDs.contains(messageID) else {
            staleMessageIDs.insert(messageID)
            return
        }
        refreshingMessageIDs.insert(messageID)
        let client = client
        let chatID = chatID
        Task { [weak self] in
            let message = try? await client.getMessage(chatId: chatID, messageId: messageID)
            guard let self else { return }
            refreshingMessageIDs.remove(messageID)
            if let message, merge(message) {
                liveLocationsChanged()
            }
            if staleMessageIDs.remove(messageID) != nil {
                refreshMessage(messageID)
            }
        }
    }

    /// A live location stays while it is shared; the opened message stays first either way.
    @discardableResult private func merge(_ message: Message) -> Bool {
        guard message.chatId == chatID else { return false }
        let index = liveMessages.firstIndex { $0.id == message.id }
        let keeps = message.id == subject.liveMessage?.id || Self.isActive(message)
        switch (index, keeps) {
        case (let index?, true):
            liveMessages[index] = message
        case (let index?, false):
            liveMessages.remove(at: index)
        case (nil, true):
            liveMessages.append(message)
        case (nil, false):
            return false
        }
        return true
    }

    private func liveLocationsChanged() {
        for message in liveMessages {
            loadSender(of: message)
        }
        updateLiveAnnotations()
        updateLiveTravelTimes()
        reloadRows()
        updateProximityState()
    }

    /// Telegram redraws the times every 10 seconds; a live location whose period has ended leaves the list.
    private func liveTimerFired() {
        let subjectID = subject.liveMessage?.id
        let count = liveMessages.count
        liveMessages.removeAll { $0.id != subjectID && !Self.isActive($0) }
        if liveMessages.count != count {
            liveLocationsChanged()
        } else {
            updateLiveTravelTimes()
            reloadRows()
        }
    }

    private func loadSender(of message: Message) {
        let senderID = message.senderId
        let key = LocationSender.key(of: senderID)
        guard senders[key] == nil, !loadingSenders.contains(key) else { return }
        loadingSenders.insert(key)
        let client = client
        Task { [weak self] in
            let sender = await LocationSender.load(senderID, client: client)
            guard let self else { return }
            loadingSenders.remove(key)
            guard let sender else { return }
            senders[key] = sender
            senderLoaded(key)
        }
    }

    private func senderLoaded(_ key: Int64) {
        for annotation in liveAnnotations.values where annotation.senderKey == key {
            (mapView.view(for: annotation) as? LiveLocationAnnotationView)?.configure(
                sender: senders[key],
                client: client,
            )
        }
        if showsOwnAnnotation, let own = ownLiveMessage, LocationSender.key(of: own.senderId) == key {
            (mapView.view(for: mapView.userLocation) as? LiveLocationAnnotationView)?.configure(
                sender: senders[key],
                client: client,
            )
        }
        reloadRows()
    }

    /// LocationMapNode's annotations: a pin for everyone else's live location, and the account's own on the user's
    /// location as Telegram's userLocationAnnotation.
    private func updateLiveAnnotations() {
        let own = ownLiveMessage
        let shown = liveMessages.filter { $0.id != own?.id }
        let shownIDs = Set(shown.map(\.id))
        for (messageID, annotation) in liveAnnotations where !shownIDs.contains(messageID) {
            mapView.removeAnnotation(annotation)
            liveAnnotations[messageID] = nil
        }
        for message in shown {
            guard let coordinate = Self.coordinate(of: message) else { continue }
            if let annotation = liveAnnotations[message.id] {
                if annotation.coordinate.latitude != coordinate.latitude
                    || annotation.coordinate.longitude != coordinate.longitude
                {
                    annotation.coordinate = coordinate
                }
            } else {
                let annotation = LiveLocationAnnotation(
                    messageID: message.id,
                    senderKey: LocationSender.key(of: message.senderId),
                )
                annotation.coordinate = coordinate
                liveAnnotations[message.id] = annotation
                mapView.addAnnotation(annotation)
            }
        }
        if (own != nil) != showsOwnAnnotation {
            showsOwnAnnotation = own != nil
            // MapKit asks for the user's location view again: the avatar, or the standard dot.
            if mapView.showsUserLocation {
                mapView.showsUserLocation = false
                mapView.showsUserLocation = true
            }
        }
        updateShowAllButton()
        if showsAllLiveLocations, !didShowAllLiveLocations, !liveAnnotations.isEmpty {
            didShowAllLiveLocations = true
            showAllLiveLocations()
        }
    }

    /// Telegram's right bar button for a live location: Show All while there are pins.
    private func updateShowAllButton() {
        let showsAll = !liveAnnotations.isEmpty
        guard showsAll != (navigationItem.rightBarButtonItem != nil) else { return }
        guard showsAll else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        let action = UIAction(title: L10n.telegram("Map.LiveLocationShowAll")) { [weak self] _ in
            self?.showAllLiveLocations()
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: action)
    }

    /// LocationMapNode.showAll: the user and every pin in view, each with 50 meters around it.
    private func showAllLiveLocations() {
        var coordinates = liveAnnotations.values.map(\.coordinate)
        if let userLocation {
            coordinates.append(userLocation.coordinate)
        }
        var zoomRect: MKMapRect?
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            let side = MKMapPointsPerMeterAtLatitude(coordinate.latitude) * 100
            let rect = MKMapRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
            zoomRect = zoomRect.map { $0.union(rect) } ?? rect
        }
        guard let zoomRect else { return }
        mapView.setUserTrackingMode(.none, animated: false)
        mapView.setVisibleMapRect(
            zoomRect,
            edgePadding: UIEdgeInsets(top: 80, left: 48, bottom: 32, right: 48),
            animated: true,
        )
    }

    /// Telegram's travel times for each live location: MapKit's estimates once the user's location is known, asked
    /// for again when they are a minute old.
    private func updateLiveTravelTimes() {
        guard userLocation != nil, !accessDenied else { return }
        let now = Foundation.Date()
        for message in liveMessages where !message.isOutgoing {
            let messageID = message.id
            if let times = liveTravelTimes[messageID], now.timeIntervalSince(times.date) < Self.travelTimeLifetime {
                continue
            }
            guard liveTravelTasks[messageID] == nil, let coordinate = Self.coordinate(of: message) else { continue }
            liveTravelTasks[messageID] = Task { [weak self] in
                async let driving = LocationTravelTime.calculate(to: coordinate, by: .driving)
                let walking = await LocationTravelTime.calculate(to: coordinate, by: .walking)
                let drivingResult = await driving
                guard let self, !Task.isCancelled else { return }
                liveTravelTasks[messageID] = nil
                liveTravelTimes[messageID] = LiveTravelTimes(
                    date: Foundation.Date(),
                    driving: drivingResult,
                    walking: walking,
                )
                reloadRows()
            }
        }
    }

    /// Telegram's sendLiveLocation: location access, then the period from makeLiveLocationDurationContextController,
    /// which asks how much longer when extending.
    private func presentLivePeriods(extend: Bool, sourceView: UIView?) {
        guard !accessDenied else {
            presentAccessDenied()
            return
        }
        guard locationManager.authorizationStatus != .notDetermined else {
            locationManager.requestWhenInUseAuthorization()
            return
        }
        let description =
            if extend {
                L10n.telegram("Map.LiveLocationExtendDescription")
            } else {
                (peerName.map { L10n.telegram("Map.LiveLocationPrivateNewDescription", $0) }
                    ?? L10n.telegram("Map.LiveLocationGroupNewDescription"))
                    .replacingOccurrences(of: "**", with: "")
            }
        let sheet = UIAlertController(title: nil, message: description, preferredStyle: .actionSheet)
        for period in LocationPickerViewController.livePeriods {
            let title = LocationPickerViewController.livePeriodTitle(period)
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                if extend {
                    self?.extendLiveLocation(by: period)
                } else {
                    self?.shareLiveLocation(period: period)
                }
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            let anchor = sourceView ?? tableView
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
        }
        present(sheet, animated: true)
    }

    /// The user's location as a live location for the period, with a proximity alert's radius; the map then shows
    /// everyone, except after an alert was set.
    @discardableResult private func shareLiveLocation(
        period: Int,
        proximityAlertRadius: Int = 0,
        showsAll: Bool = true,
    ) -> Bool {
        guard let send = sendLiveLocation, let location = userLocation ?? mapView.userLocation.location else {
            return false
        }
        let accuracy = location.horizontalAccuracy > 0 ? min(location.horizontalAccuracy, Self.maximumAccuracy) : 0
        send(.inputMessageLiveLocation(TDNativeInputMessageLiveLocation(location: TDNativeLiveLocation(
            location: TDNativeLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: accuracy,
            ),
            livePeriod: period,
            heading: 0,
            proximityAlertRadius: proximityAlertRadius,
        ))))
        if showsAll {
            showAllLiveLocations()
        }
        return true
    }

    /// RequestEditMessage's extendPeriod: the period grows by the chosen one, or becomes indefinite.
    private func extendLiveLocation(by period: Int) {
        guard let own = ownLiveMessage, case .messageLiveLocation(let live) = own.content else { return }
        let indefinite = LiveLocationManager.indefinitePeriod
        let location = LiveLocation(
            location: Location(
                latitude: live.location.location.latitude,
                longitude: live.location.location.longitude,
                horizontalAccuracy: live.location.location.horizontalAccuracy,
            ),
            livePeriod: period == indefinite ? indefinite : live.location.livePeriod + period,
            heading: live.location.heading,
            proximityAlertRadius: live.location.proximityAlertRadius,
        )
        let client = client
        let chatID = own.chatId
        let messageID = own.id
        Task {
            _ = try? await client.editMessageLiveLocation(
                chatId: chatID,
                messageId: messageID,
                replyMarkup: nil,
                location: location,
            )
        }
    }

    /// Telegram's stopLiveLocation: cancelLiveLocation for the chat, and the viewer closes.
    private func stopLiveLocation() {
        guard let source else { return }
        LiveLocationManager.shared.stop(chatID: chatID, source: source)
        dismiss(animated: true)
    }

    // Proximity alert

    /// The chat's kind for the bell: Telegram's peer namespace, and the message's author.
    private func loadProximityChat() {
        guard let chatID = subject.chatID else { return }
        let client = client
        let sender = subject.sender
        proximityChatTask = Task { [weak self] in
            guard let chat = try? await client.getChat(chatId: chatID) else { return }
            var isBroadcastPost = false
            if case .messageSenderChat(let value)? = sender {
                var senderChat: Chat? = chat
                if value.chatId != chatID {
                    senderChat = try? await client.getChat(chatId: value.chatId)
                }
                if case .chatTypeSupergroup(let supergroup)? = senderChat?.type {
                    isBroadcastPost = supergroup.isChannel
                }
            }
            var isUser = false
            if case .chatTypePrivate = chat.type {
                isUser = true
            }
            guard let self, !Task.isCancelled else { return }
            proximityChatTask = nil
            proximityChat = ProximityChat(isUser: isUser, isBroadcastPost: isBroadcastPost, title: chat.title)
            updateProximityState()
        }
    }

    /// LocationViewControllerNode's proximityNotification: on with the radius of the account's own live location,
    /// else off while someone else shares theirs, and off in a group or a secret chat anyway; a channel's post has
    /// none. An alert being set or cancelled shows as done. BetterTG also hides the bell where no alert can be set:
    /// without an own live location in a chat where one can't be shared.
    private func proximityState() -> (notification: Bool?, radius: Int?) {
        guard let proximityChat else { return (nil, nil) }
        var notification: Bool?
        var radius: Int?
        if isLiveView {
            if let own = ownLiveMessage, case .messageLiveLocation(let live) = own.content,
               live.location.proximityAlertRadius > 0
            {
                notification = true
                radius = live.location.proximityAlertRadius
            }
            if notification == nil, liveMessages.contains(where: { !$0.isOutgoing && Self.isActive($0) }) {
                notification = false
            }
        }
        if notification == true, cancellingProximityRadius {
            notification = false
            radius = nil
        } else if let updatingProximityRadius {
            notification = true
            radius = updatingProximityRadius
        }
        if !proximityChat.isUser, notification == nil {
            notification = false
        }
        if proximityChat.isBroadcastPost {
            notification = nil
        }
        if ownProximityMessageID == nil, !canShareLiveLocation || sendLiveLocation == nil {
            notification = nil
        }
        return (notification, radius)
    }

    /// LocationMapHeaderNode's notification button and LocationMapNode's circle of the alert set; the first time the
    /// bell offers an alert, its hint shows.
    private func updateProximityState() {
        guard isViewLoaded else { return }
        let state = proximityState()
        proximityNotification = state.notification
        proximityButton.isHidden = state.notification == nil
        proximityButton.configuration?.image = UIImage(
            systemName: state.notification == true ? "bell.slash" : "bell.and.waves.left.and.right",
        )
        proximityButton.accessibilityTraits = state.notification == true ? [.button, .selected] : .button
        activeProximityRadius = state.notification == nil ? nil : state.radius
        updateProximityCircle()
        if state.notification == false, !displayedProximityTip {
            displayedProximityTip = true
            showProximityTipIfNeeded()
        }
    }

    /// LocationMapNode.activeProximityRadius: the alert's circle around the user's location.
    private func updateProximityCircle() {
        guard let radius = activeProximityRadius, radius > 0,
              let center = mapView.userLocation.location?.coordinate
        else {
            if let proximityCircle {
                mapView.removeOverlay(proximityCircle)
                self.proximityCircle = nil
            }
            return
        }
        if let proximityCircle {
            let moved = CLLocation(
                latitude: proximityCircle.coordinate.latitude,
                longitude: proximityCircle.coordinate.longitude,
            ).distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
            guard proximityCircle.radius != CLLocationDistance(radius) || moved >= 1 else { return }
            mapView.removeOverlay(proximityCircle)
        }
        let circle = MKCircle(center: center, radius: CLLocationDistance(radius))
        proximityCircle = circle
        mapView.addOverlay(circle)
    }

    /// The bell cancels the alert set, or picks a distance for one; using it retires the hint.
    @objc private func proximityPressed() {
        guard let proximityNotification else { return }
        hideProximityTip()
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Self.proximityTipCountKey) + 4, forKey: Self.proximityTipCountKey)
        setupProximityNotification(reset: proximityNotification)
    }

    /// Telegram's setupProximityNotification: a reset sets the own live location's radius to 0; otherwise, with
    /// location access, LocationDistancePickerScreen picks the distance while the map shows it around the user.
    private func setupProximityNotification(reset: Bool) {
        let messageID = ownProximityMessageID
        if reset {
            guard let messageID else { return }
            cancellingProximityRadius = true
            updateProximityState()
            editOwnProximityRadius(0, messageID: messageID)
            showProximityToast(title: L10n.telegram("Location.ProximityAlertCancelled"), text: "")
            return
        }
        guard !accessDenied else {
            presentAccessDenied()
            return
        }
        guard locationManager.authorizationStatus != .notDetermined else {
            locationManager.requestWhenInUseAuthorization()
            return
        }
        guard presentedViewController == nil else { return }
        setProximityIndicator(radius: 0)
        let compactDisplayTitle = proximityChat?.isUser == true ? peerName ?? proximityChat?.title : nil
        let picker = LocationDistancePickerViewController(
            compactDisplayTitle: compactDisplayTitle,
            distances: { [weak self] in self?.distancesToAllAnnotations() ?? [] },
            updated: { [weak self] distance in self?.setProximityIndicator(radius: distance) },
            completion: { [weak self] distance, picker in
                self?.proximityDistancePicked(
                    distance,
                    messageID: messageID,
                    compactDisplayTitle: compactDisplayTitle,
                    picker: picker,
                )
            },
            willDismiss: { [weak self] in self?.setProximityIndicator(radius: nil) },
        )
        present(picker, animated: true)
    }

    /// The distance goes to the account's own live location; without one Telegram asks to share it first.
    private func proximityDistancePicked(
        _ distance: Int,
        messageID: Int64?,
        compactDisplayTitle: String?,
        picker: UIViewController,
    ) {
        guard let messageID else {
            picker.dismiss(animated: true) { [weak self] in
                self?.presentLiveLocationRequired(distance: distance, compactDisplayTitle: compactDisplayTitle)
            }
            return
        }
        updatingProximityRadius = distance
        updateProximityState()
        editOwnProximityRadius(distance, messageID: messageID)
        showProximityToast(
            title: L10n.telegram("Location.ProximityAlertSetTitle"),
            text: proximityAlertSetText(distance, compactDisplayTitle: compactDisplayTitle),
        )
        picker.dismiss(animated: true)
    }

    /// Location.LiveLocationRequired: the alert works with the account's live location here, which Share Location
    /// sends for 30 minutes with the radius.
    private func presentLiveLocationRequired(distance: Int, compactDisplayTitle: String?) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.telegram("Location.LiveLocationRequired.Title"),
            message: L10n.telegram("Location.LiveLocationRequired.Description"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(
            title: L10n.telegram("Location.LiveLocationRequired.ShareLocation"),
            style: .default,
        ) { [weak self] _ in
            guard let self else { return }
            let period = Self.proximityLivePeriod
            guard shareLiveLocation(period: period, proximityAlertRadius: distance, showsAll: false) else { return }
            showProximityToast(
                title: L10n.telegram("Location.ProximityAlertSetTitle"),
                text: proximityAlertSetText(distance, compactDisplayTitle: compactDisplayTitle),
            )
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    /// LiveLocationManager edits the message, so its next locations keep the radius; the change shows as done until
    /// half a second after the edit.
    private func editOwnProximityRadius(_ radius: Int, messageID: Int64) {
        let chatID = chatID
        let source = source
        Task { [weak self] in
            if let source {
                await LiveLocationManager.shared.setProximityAlertRadius(
                    radius,
                    chatID: chatID,
                    messageID: messageID,
                    source: source,
                )
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let self else { return }
            if radius == 0 {
                cancellingProximityRadius = false
            } else {
                updatingProximityRadius = nil
            }
            updateProximityState()
        }
    }

    /// LocationViewControllerNode.setProximityIndicator: while a distance is picked the map buttons hide, the list
    /// makes room, the map dims around a clear circle and fits the radius around the user into it; afterwards the map
    /// returns to the user.
    private func setProximityIndicator(radius: Int?) {
        guard isViewLoaded else { return }
        let wasShown = proximityIndicatorRadius != nil
        proximityIndicatorRadius = radius
        if (radius != nil) != wasShown {
            setMapButtonsHidden(radius != nil)
            updateTableHeight()
            UIView.animate(withDuration: 0.3) { self.view.layoutIfNeeded() }
        }
        updateProximityDim()
        guard let location = mapView.userLocation.location ?? userLocation else { return }
        mapView.setUserTrackingMode(.none, animated: false)
        guard let radius else {
            mapView.setRegion(MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan), animated: true)
            return
        }
        guard radius > 0, let hole = proximityDimHole else { return }
        let side = MKMapPointsPerMeterAtLatitude(location.coordinate.latitude) * Double(radius) * 2
        let center = MKMapPoint(location.coordinate)
        mapView.setVisibleMapRect(
            MKMapRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
            edgePadding: UIEdgeInsets(
                top: hole.minY,
                left: hole.minX,
                bottom: mapView.bounds.height - hole.maxY,
                right: mapView.bounds.width - hole.maxX,
            ),
            animated: true,
        )
    }

    /// LocationMapNode's proximityDimView: the clear circle sits in the middle of the map left above the picker.
    private func updateProximityDim() {
        guard proximityIndicatorRadius != nil else {
            proximityDimHole = nil
            guard proximityDimView.image != nil else { return }
            UIView.transition(with: proximityDimView, duration: 0.3, options: .transitionCrossDissolve) {
                self.proximityDimView.image = nil
            }
            return
        }
        let size = mapView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let panelTop = view.bounds.height - LocationDistancePickerViewController.contentHeight
            - view.safeAreaInsets.bottom
        let visibleHeight = max(0, min(mapView.frame.maxY, panelTop) - mapView.frame.minY)
        let diameter = max(0, min(Self.proximityHoleDiameter, size.width - 32, visibleHeight - 16))
        let hole = CGRect(
            x: floor((size.width - diameter) / 2),
            y: floor((visibleHeight - diameter) / 2),
            width: diameter,
            height: diameter,
        )
        guard hole != proximityDimHole || proximityDimView.image?.size != size else { return }
        let isFirst = proximityDimView.image == nil
        proximityDimHole = hole
        proximityDimView.image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.withAlphaComponent(0.4).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.setBlendMode(.clear)
            context.cgContext.fillEllipse(in: hole)
        }
        guard isFirst else { return }
        proximityDimView.alpha = 0
        UIView.animate(withDuration: 0.2) { self.proximityDimView.alpha = 1 }
    }

    /// LocationMapHeaderNode.forceIsHidden.
    private func setMapButtonsHidden(_ hidden: Bool) {
        hideProximityTip()
        let buttons = [mapModeButton, trackingButton, proximityButton]
        for button in buttons {
            button.isUserInteractionEnabled = !hidden
        }
        UIView.animate(withDuration: 0.2) {
            for button in buttons {
                button.alpha = hidden ? 0 : 1
            }
        }
    }

    /// LocationMapNode.distancesToAllAnnotations: how far the user is from every pin but their own, nearest first.
    private func distancesToAllAnnotations() -> [Double] {
        guard let location = mapView.userLocation.location ?? userLocation else { return [] }
        let coordinates = isLiveView ? liveAnnotations.values.map(\.coordinate) : [subject.coordinate]
        return coordinates
            .map { location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
            .sorted()
    }

    /// Location.ProximityAlertSetText with the other user's name, or the group text.
    private func proximityAlertSetText(_ distance: Int, compactDisplayTitle: String?) -> String {
        let distanceText = shortDistance(CLLocationDistance(distance))
        guard let compactDisplayTitle else {
            return L10n.telegram("Location.ProximityAlertSetTextGroup", distanceText)
        }
        return L10n.telegram("Location.ProximityAlertSetText", compactDisplayTitle, distanceText)
    }

    /// UndoOverlayController's setProximityAlert.
    private func showProximityToast(title: String, text: String) {
        TelegramUndoToast.show(title: title, text: text, in: view, bottomInset: 8, undo: nil)
    }

    /// Telegram's displayProximityAlertTooltip: Alert when ... is close, or when any group member is, by the bell for
    /// three seconds, on at most three openings.
    private func showProximityTipIfNeeded() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: Self.proximityTipCountKey)
        guard count < 3, let proximityChat, proximityIndicatorRadius == nil else { return }
        defaults.set(count + 1, forKey: Self.proximityTipCountKey)
        let text =
            if proximityChat.isUser {
                L10n.telegram("Location.ProximityTip", peerName ?? proximityChat.title)
            } else {
                L10n.telegram("Location.ProximityGroupTip")
            }
        hideProximityTip()
        let tip = LocationTipView(text: text)
        tip.translatesAutoresizingMaskIntoConstraints = false
        tip.alpha = 0
        view.addSubview(tip)
        NSLayoutConstraint.activate([
            tip.trailingAnchor.constraint(equalTo: proximityButton.leadingAnchor, constant: -4),
            tip.centerYAnchor.constraint(equalTo: proximityButton.centerYAnchor),
            tip.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])
        proximityTipView = tip
        UIView.animate(withDuration: 0.2) { tip.alpha = 1 }
        UIAccessibility.post(notification: .announcement, argument: text)
        proximityTipTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.hideProximityTip()
        }
    }

    private func hideProximityTip() {
        proximityTipTask?.cancel()
        proximityTipTask = nil
        guard let tip = proximityTipView else { return }
        proximityTipView = nil
        UIView.animate(withDuration: 0.2) {
            tip.alpha = 0
        } completion: { _ in
            tip.removeFromSuperview()
        }
    }

    /// Telegram's requestDirections: Apple Maps at once when no other app can open the place, else the apps to choose
    /// from.
    private func requestDirections(
        _ directions: LocationDirections,
        coordinate: CLLocationCoordinate2D,
        venue: LocationPickerVenue?,
        name: String?,
        sourceView: UIView?,
    ) {
        let options = LocationOpenInOption.available(coordinate: coordinate, venue: venue, directions: directions)
        guard options.count > 1 else {
            openInMaps(coordinate: coordinate, venue: venue, directions: directions, name: name)
            return
        }
        presentOpenIn(
            options,
            coordinate: coordinate,
            venue: venue,
            directions: directions,
            name: name,
            share: nil,
        ) { popover in
            let anchor = sourceView ?? self.tableView
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
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
        presentOpenIn(
            options,
            coordinate: subject.coordinate,
            venue: subject.venue,
            directions: nil,
            name: nil,
            share: shareAction,
        ) { popover in
            popover.sourceItem = item
        }
    }

    private func presentOpenIn(
        _ options: [LocationOpenInOption],
        coordinate: CLLocationCoordinate2D,
        venue: LocationPickerVenue?,
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
                    self?.openInMaps(coordinate: coordinate, venue: venue, directions: directions, name: name)
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
    private func openInMaps(
        coordinate: CLLocationCoordinate2D,
        venue: LocationPickerVenue?,
        directions: LocationDirections?,
        name: String?,
    ) {
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil,
        )
        item.name = venue?.title ?? name
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

    /// A list icon: the glyph in white on a colored circle; LocationActionListItem's extend icon adds a plus.
    private func icon(symbol: String, color: UIColor, addsPlus: Bool = false) -> UIImage {
        let key = "\(symbol)|\(color.description)|\(addsPlus)"
        if let cached = iconCache[key] { return cached }
        let size = CGSize(width: 40, height: 40)
        let glyph = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        )?.withTintColor(.white, renderingMode: .alwaysOriginal)
        let image = UIGraphicsImageRenderer(size: size)
            .image { context in
                color.setFill()
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
                if let glyph {
                    let offset: CGFloat = addsPlus ? 3 : 0
                    glyph.draw(in: CGRect(
                        x: (size.width - glyph.size.width) / 2 + offset,
                        y: (size.height - glyph.size.height) / 2,
                        width: glyph.size.width,
                        height: glyph.size.height,
                    ))
                }
                guard addsPlus else { return }
                let cgContext = context.cgContext
                cgContext.setStrokeColor(UIColor.white.cgColor)
                cgContext.setLineWidth(2)
                cgContext.setLineCap(.round)
                let length: CGFloat = 6
                let center = CGPoint(x: 11, y: 13)
                cgContext.move(to: CGPoint(x: center.x - length / 2, y: center.y))
                cgContext.addLine(to: CGPoint(x: center.x + length / 2, y: center.y))
                cgContext.move(to: CGPoint(x: center.x, y: center.y - length / 2))
                cgContext.addLine(to: CGPoint(x: center.x, y: center.y + length / 2))
                cgContext.strokePath()
            }
            .withRenderingMode(.alwaysOriginal)
        iconCache[key] = image
        return image
    }
}
