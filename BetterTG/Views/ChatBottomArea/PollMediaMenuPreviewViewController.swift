// PollMediaMenuPreviewViewController.swift

import ImageIO
import MapKit
import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - PollMediaMenuPreviewViewController

/// The preview above openAttachMediaContextMenu's Replace and Delete for media being composed: a photo or a video's
/// frame on black at its aspect, as GalleryController shows media in a previewing context without its controls; a
/// place on LocationViewController's `isPreview` map, which is the map alone with the place's pin; or a file's icon
/// and name.
final class PollMediaMenuPreviewViewController: UIViewController, MKMapViewDelegate {
    private static let annotationIdentifier = "PollMediaMenuPreviewPin"
    /// LocationViewController's span around the place it opens on.
    private static let mapSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)

    private let media: PollDraftMedia
    private let imageView = UIImageView()
    private var venue: LocationPickerVenue?
    private var imageRequest: Task<Void, Never>?

    /// The picked file's name without the store's identifier prefix.
    private var fileName: String? {
        guard let name = media.fileURLs.first?.lastPathComponent, !name.isEmpty else { return nil }
        let prefix = name.prefix(37)
        guard prefix.count == 37, prefix.last == "-", UUID(uuidString: String(prefix.dropLast())) != nil else {
            return name
        }
        return String(name.dropFirst(37))
    }

    init(media: PollDraftMedia) {
        self.media = media
        super.init(nibName: nil, bundle: nil)
        switch media.preview {
        case .image(let image, _):
            // GalleryController's preferredContentSizeForLayout: the item's size, fitted by the menu.
            preferredContentSize = CGSize(
                width: image.size.width * image.scale,
                height: image.size.height * image.scale,
            )
        case .audio, .file, .link, .sticker:
            preferredContentSize = CGSize(width: 4, height: 3)
        case .location:
            break
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        switch media.preview {
        case .image(let image, let isVideo):
            showImage(image, isVideo: isVideo)
        case .location(let location, let venue):
            showMap(location, venue: venue)
        case .audio:
            showFile(systemName: "music.note")
        case .file, .link, .sticker:
            showFile(systemName: "doc.fill")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        imageRequest?.cancel()
        imageRequest = nil
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.annotationIdentifier, for: annotation)
        guard let marker = view as? MKMarkerAnnotationView else { return view }
        marker.markerTintColor = venue?.iconColor ?? .systemRed
        marker.glyphImage = venue.flatMap { UIImage(systemName: $0.symbolName) }
        marker.canShowCallout = false
        marker.titleVisibility = .hidden
        marker.displayPriority = .required
        return marker
    }

    /// The thumbnail's image at once, then a picked photo's file decoded at the preview's size.
    private func showImage(_ image: UIImage, isVideo: Bool) {
        view.backgroundColor = .black
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        pin(imageView)
        if isVideo {
            let button = UIView()
            button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            button.layer.cornerRadius = 25
            button.translatesAutoresizingMaskIntoConstraints = false
            let icon = UIImageView(image: UIImage(
                systemName: "play.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold),
            ))
            icon.tintColor = .white
            icon.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(icon)
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 50),
                button.heightAnchor.constraint(equalToConstant: 50),
                button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                icon.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            return
        }
        guard media.fileURLs.count == 1, let url = media.fileURLs.first,
              UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else { return }
        imageRequest = Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                pollMediaMenuPreviewImage(at: url)
            }.value
            guard let self, !Task.isCancelled, let decoded else { return }
            imageView.image = decoded
        }
    }

    private func showMap(_ location: Location, venue: TDNativeVenue?) {
        let mapView = MKMapView()
        mapView.delegate = self
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Self.annotationIdentifier,
        )
        pin(mapView)
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        mapView.setRegion(MKCoordinateRegion(center: coordinate, span: Self.mapSpan), animated: false)
        self.venue = venue.map { LocationPickerVenue(venue: $0) }
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        mapView.addAnnotation(annotation)
    }

    private func showFile(systemName: String) {
        view.backgroundColor = .secondarySystemBackground
        let icon = UIImageView(image: UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .regular),
        ))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .center
        let stack = UIStackView(arrangedSubviews: [icon])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let name = fileName {
            let label = UILabel()
            label.text = name
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = .label
            label.numberOfLines = 2
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            stack.addArrangedSubview(label)
        }
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    private func pin(_ subview: UIView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: view.topAnchor),
            subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

/// A picked photo decoded at a size the preview fills, its orientation applied.
private func pollMediaMenuPreviewImage(at url: URL) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1280,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
}
