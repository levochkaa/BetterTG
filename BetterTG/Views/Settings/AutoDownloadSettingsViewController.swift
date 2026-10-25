// AutoDownloadSettingsViewController.swift

import UIKit

// MARK: - AutoDownloadSummary

/// The summaries Telegram's auto-download rows show.
@MainActor enum AutoDownloadSummary {
    /// DataAndStorageSettingsController's stringForAutoDownloadSetting: "Disabled", or the types with their sizes,
    /// such as "Media (10 MB), Files (3 MB)".
    static func connection(_ networkType: MediaAutoDownload.NetworkType) -> String {
        let autoDownload = MediaAutoDownload.shared
        guard autoDownload.connection(for: networkType).enabled else {
            return L10n.telegram("ChatSettings.AutoDownloadSettings.OffForAll")
        }
        let categories = autoDownload.categories(for: networkType)
        let photo = categories.photo.isEnabledForAnyPeer
        let videoSize = categories.video.isEnabledForAnyPeer ? categories.video.sizeLimit : nil
        let fileSize = categories.file.isEnabledForAnyPeer ? categories.file.sizeLimit : nil
        var types = [String]()
        if photo, videoSize == nil {
            types.append(L10n.telegram("ChatSettings.AutoDownloadSettings.TypePhoto"))
        }
        if let videoSize {
            types.append(L10n.telegram(
                photo ? "ChatSettings.AutoDownloadSettings.TypeMedia" : "ChatSettings.AutoDownloadSettings.TypeVideo",
                MediaAutoDownload.sizeString(videoSize),
            ))
        }
        if let fileSize {
            types.append(L10n.telegram(
                "ChatSettings.AutoDownloadSettings.TypeFile",
                MediaAutoDownload.sizeString(fileSize),
            ))
        }
        guard !types.isEmpty else { return L10n.telegram("ChatSettings.AutoDownloadSettings.OffForAll") }
        return types.joined(separator: L10n.telegram("ChatSettings.AutoDownloadSettings.Delimeter"))
    }

    /// AutodownloadConnectionTypeController's stringForAutomaticDownloadPeers: "On for all chats", "Up to 10 MB for
    /// Contacts and Groups", "Off for all chats".
    static func peers(_ category: MediaAutoDownloadCategory, showsSize: Bool) -> String {
        let size = showsSize ? MediaAutoDownload.sizeString(category.sizeLimit) : nil
        if MediaAutoDownload.PeerType.allCases.allSatisfy(category.isEnabled(for:)) {
            return size.map { L10n.telegram("AutoDownloadSettings.UpToForAll", $0) }
                ?? L10n.telegram("AutoDownloadSettings.OnForAll")
        }
        let types = MediaAutoDownload.PeerType.allCases.filter(category.isEnabled(for:)).map { type in
            switch type {
            case .contact: L10n.telegram("AutoDownloadSettings.TypeContacts")
            case .otherPrivate: L10n.telegram("AutoDownloadSettings.TypePrivateChats")
            case .group: L10n.telegram("AutoDownloadSettings.TypeGroupChats")
            case .channel: L10n.telegram("AutoDownloadSettings.TypeChannels")
            }
        }
        guard !types.isEmpty else { return L10n.telegram("AutoDownloadSettings.OffForAll") }
        var list = ""
        for (index, type) in types.enumerated() {
            if index > 0 {
                list += L10n.telegram(index == types.count - 1
                    ? "AutoDownloadSettings.LastDelimeter"
                    : "AutoDownloadSettings.Delimeter")
            }
            list += type
        }
        return size.map { L10n.telegram("AutoDownloadSettings.UpToFor", $0, list) }
            ?? L10n.telegram("AutoDownloadSettings.OnFor", list)
    }
}

// MARK: - AutoDownloadConnectionViewController

/// Telegram's AutodownloadConnectionTypeController for cellular or Wi-Fi: Auto-Download Media, the Low, Medium or
/// High data usage (with Custom placed by size once a type was edited), then Photos, Videos and Files with whom and
/// up to what size they download for.
final class AutoDownloadConnectionViewController: SettingsListViewController {
    private let networkType: MediaAutoDownload.NetworkType

    init(networkType: MediaAutoDownload.NetworkType) {
        self.networkType = networkType
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram(networkType == .cellular
            ? "AutoDownloadSettings.CellularTitle"
            : "AutoDownloadSettings.WifiTitle")
        tableView.register(
            AutoDownloadDataUsageCell.self,
            forCellReuseIdentifier: AutoDownloadDataUsageCell.reuseIdentifier,
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override func makeSections() -> [SettingsSection] {
        let autoDownload = MediaAutoDownload.shared
        let networkType = networkType
        let enabled = autoDownload.connection(for: networkType).enabled
        let categories = autoDownload.categories(for: networkType)
        let types: [(MediaAutoDownload.Category, String, Bool)] = [
            (.photo, "AutoDownloadSettings.Photos", false),
            (.video, "AutoDownloadSettings.Videos", true),
            (.file, "AutoDownloadSettings.Files", true),
        ]
        return [
            SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("AutoDownloadSettings.AutoDownload"),
                accessory: .toggle(isOn: enabled) { [weak self] isOn in
                    MediaAutoDownload.shared.updateConnection(networkType) { $0.enabled = isOn }
                    self?.reload()
                },
            )]),
            // The data usage cell stands in for this row.
            SettingsSection(header: L10n.telegram("AutoDownloadSettings.DataUsage"), rows: [SettingsRow(title: "")]),
            SettingsSection(
                header: L10n.telegram("AutoDownloadSettings.MediaTypes"),
                footer: L10n.telegram("AutoDownloadSettings.VoiceMessagesInfo"),
                rows: types.map { category, title, showsSize in
                    SettingsRow(
                        title: L10n.telegram(title),
                        detail: AutoDownloadSummary.peers(categories[category], showsSize: showsSize),
                        style: .subtitle,
                        accessory: .disclosure,
                        isEnabled: enabled,
                    ) { [weak self] in
                        self?.navigationController?.pushViewController(
                            AutoDownloadCategoryViewController(networkType: networkType, category: category),
                            animated: true,
                        )
                    }
                },
            ),
        ]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 1 else { return super.tableView(tableView, cellForRowAt: indexPath) }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AutoDownloadDataUsageCell.reuseIdentifier,
            for: indexPath,
        )
        let autoDownload = MediaAutoDownload.shared
        let connection = autoDownload.connection(for: networkType)
        // AutodownloadConnectionTypeController: Custom sits among the presets by how much it downloads.
        var stops: [MediaAutoDownload.Preset] = [.low, .medium, .high]
        if let custom = connection.custom {
            let sizes = stops.map { autoDownload.preset($0)?.downloadedSize ?? 0 }
            let position = sizes.firstIndex { custom.downloadedSize < $0 } ?? sizes.count
            stops.insert(.custom, at: position)
        }
        let networkType = networkType
        (cell as? AutoDownloadDataUsageCell)?.configure(
            stops: stops,
            selected: connection.preset,
            isEnabled: connection.enabled,
        ) { [weak self] preset in
            MediaAutoDownload.shared.updateConnection(networkType) { $0.preset = preset }
            self?.reload(sections: [2])
        }
        return cell
    }
}

// MARK: - AutoDownloadCategoryViewController

/// Telegram's AutodownloadMediaCategoryController: whom photos, videos or files download for, and for videos and
/// files the largest size on AutodownloadSizeLimitItem's slider. An edit makes the connection's preset custom.
/// BetterTG doesn't preload the start of larger videos, so Preload Larger Videos has no counterpart.
final class AutoDownloadCategoryViewController: SettingsListViewController {
    private let networkType: MediaAutoDownload.NetworkType
    private let category: MediaAutoDownload.Category

    init(networkType: MediaAutoDownload.NetworkType, category: MediaAutoDownload.Category) {
        self.networkType = networkType
        self.category = category
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title =
            switch category {
            case .photo: L10n.telegram("AutoDownloadSettings.PhotosTitle")
            case .video: L10n.telegram("AutoDownloadSettings.VideosTitle")
            case .file: L10n.telegram("AutoDownloadSettings.DocumentsTitle")
            }
        tableView.register(
            AutoDownloadSizeLimitCell.self,
            forCellReuseIdentifier: AutoDownloadSizeLimitCell.reuseIdentifier,
        )
    }

    override func makeSections() -> [SettingsSection] {
        let settings = MediaAutoDownload.shared.categories(for: networkType)[category]
        let networkType = networkType
        let category = category
        let peers: [(MediaAutoDownload.PeerType, String)] = [
            (.contact, "AutoDownloadSettings.Contacts"),
            (.otherPrivate, "AutoDownloadSettings.PrivateChats"),
            (.group, "AutoDownloadSettings.GroupChats"),
            (.channel, "AutoDownloadSettings.Channels"),
        ]
        let header =
            switch category {
            case .photo: L10n.telegram("AutoDownloadSettings.AutodownloadPhotos")
            case .video: L10n.telegram("AutoDownloadSettings.AutodownloadVideos")
            case .file: L10n.telegram("AutoDownloadSettings.AutodownloadFiles")
            }
        var sections = [SettingsSection(header: header, rows: peers.map { peerType, title in
            SettingsRow(
                title: L10n.telegram(title),
                accessory: .toggle(isOn: settings.isEnabled(for: peerType)) { isOn in
                    MediaAutoDownload.shared.updateCategories(networkType) { $0[category][peerType] = isOn }
                },
            )
        })]
        if category != .photo {
            // The size slider's cell stands in for this row.
            sections.append(SettingsSection(
                header: L10n.telegram(category == .video
                    ? "AutoDownloadSettings.MaxVideoSize"
                    : "AutoDownloadSettings.MaxFileSize"),
                rows: [SettingsRow(title: "")],
            ))
        }
        return sections
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 1 else { return super.tableView(tableView, cellForRowAt: indexPath) }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AutoDownloadSizeLimitCell.reuseIdentifier,
            for: indexPath,
        )
        let networkType = networkType
        let category = category
        (cell as? AutoDownloadSizeLimitCell)?.configure(
            size: MediaAutoDownload.shared.categories(for: networkType)[category].sizeLimit,
        ) { size in
            MediaAutoDownload.shared.updateCategories(networkType) { $0[category].sizeLimit = size }
        }
        return cell
    }
}

// MARK: - AutoDownloadDataUsageCell

/// AutodownloadDataUsagePickerItem: Low, Medium and High (and Custom) in 13 pt over a slider that snaps to them.
private final class AutoDownloadDataUsageCell: UITableViewCell {
    static let reuseIdentifier = "AutoDownloadDataUsageCell"

    private let slider = UISlider()
    private var labels = [UILabel]()
    private var stops = [MediaAutoDownload.Preset]()
    private var selectedIndex = 0
    private var onChange: ((MediaAutoDownload.Preset) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        slider.minimumTrackTintColor = .tintColor
        slider.addAction(UIAction { [weak self] _ in self?.sliderMoved() }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in self?.snap() }, for: [.touchUpInside, .touchUpOutside])
        contentView.addSubview(slider)
        NSLayoutConstraint.activate([contentView.heightAnchor.constraint(equalToConstant: 88)])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let delta = (width - 25 * 2) / CGFloat(max(1, labels.count - 1))
        for (index, label) in labels.enumerated() {
            label.sizeToFit()
            let position = 25 + delta * CGFloat(index)
            let x = max(18, min(width - 18 - label.bounds.width, position - label.bounds.width / 2))
            label.frame.origin = CGPoint(x: x, y: 15)
        }
        slider.frame = CGRect(x: 15, y: 37, width: width - 30, height: 44)
    }

    func configure(
        stops: [MediaAutoDownload.Preset],
        selected: MediaAutoDownload.Preset,
        isEnabled: Bool,
        onChange: @escaping (MediaAutoDownload.Preset) -> Void,
    ) {
        self.stops = stops
        self.onChange = onChange
        labels.forEach { $0.removeFromSuperview() }
        labels = stops.map { preset in
            let label = UILabel()
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
            label.text =
                switch preset {
                case .low: L10n.telegram("AutoDownloadSettings.DataUsageLow")
                case .medium: L10n.telegram("AutoDownloadSettings.DataUsageMedium")
                case .high: L10n.telegram("AutoDownloadSettings.DataUsageHigh")
                case .custom: L10n.telegram("AutoDownloadSettings.DataUsageCustom")
                }
            contentView.addSubview(label)
            return label
        }
        selectedIndex = stops.firstIndex(of: selected) ?? 0
        slider.maximumValue = Float(max(1, stops.count - 1))
        slider.value = Float(selectedIndex)
        slider.isUserInteractionEnabled = isEnabled
        slider.alpha = isEnabled ? 1 : 0.4
        setNeedsLayout()
    }

    private func sliderMoved() {
        let index = Int(slider.value.rounded())
        guard index != selectedIndex, stops.indices.contains(index) else { return }
        selectedIndex = index
        UISelectionFeedbackGenerator().selectionChanged()
        onChange?(stops[index])
    }

    private func snap() {
        UIView.animate(withDuration: 0.15) { self.slider.setValue(Float(self.selectedIndex), animated: true) }
    }
}

// MARK: - AutoDownloadSizeLimitCell

/// AutodownloadSizeLimitItem: "up to 10 MB" in 17 pt above a slider from 512 KB to 1.5 GB, its ends in 13 pt, on
/// Telegram's uneven scale (1 MB at a quarter, 10 MB at half, 100 MB at three quarters).
private final class AutoDownloadSizeLimitCell: UITableViewCell {
    static let reuseIdentifier = "AutoDownloadSizeLimitCell"

    private static let stops: [(position: CGFloat, size: Int64)] = [
        (0, 512 * 1024),
        (0.257, 1024 * 1024),
        (0.520, 10 * 1024 * 1024),
        (0.763, 100 * 1024 * 1024),
        (1, 1536 * 1024 * 1024),
    ]

    private let textLabelView = UILabel()
    private let minLabel = UILabel()
    private let maxLabel = UILabel()
    private let slider = UISlider()
    private var onChange: ((Int64) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        textLabelView.font = .systemFont(ofSize: 17)
        textLabelView.textAlignment = .center
        for label in [minLabel, maxLabel] {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
        }
        minLabel.text = MediaAutoDownload.sizeString(Self.stops[0].size)
        maxLabel.text = MediaAutoDownload.sizeString(Self.stops[Self.stops.count - 1].size)
        slider.minimumTrackTintColor = .tintColor
        slider.addAction(UIAction { [weak self] _ in self?.sliderMoved() }, for: .valueChanged)
        for subview in [textLabelView, minLabel, maxLabel, slider] {
            contentView.addSubview(subview)
        }
        NSLayoutConstraint.activate([contentView.heightAnchor.constraint(equalToConstant: 88)])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        minLabel.sizeToFit()
        maxLabel.sizeToFit()
        minLabel.frame.origin = CGPoint(x: 16, y: 16)
        maxLabel.frame.origin = CGPoint(x: width - 16 - maxLabel.bounds.width, y: 16)
        textLabelView.frame = CGRect(x: 0, y: 12, width: width, height: 22)
        slider.frame = CGRect(x: 15, y: 37, width: width - 30, height: 44)
    }

    /// sliderValue(for:): the size's place between the two stops around it.
    private static func position(for size: Int64) -> CGFloat {
        for index in 1..<stops.count {
            let previous = stops[index - 1]
            let next = stops[index]
            if next.size > size {
                let fraction = CGFloat(max(0, size - previous.size)) / CGFloat(next.size - previous.size)
                return previous.position + fraction * (next.position - previous.position)
            }
        }
        return 1
    }

    /// sizeValue(for:): the size at a place on the slider.
    private static func size(for position: CGFloat) -> Int64 {
        for index in 1..<stops.count {
            let previous = stops[index - 1]
            let next = stops[index]
            if next.position > position {
                let fraction = (position - previous.position) / (next.position - previous.position)
                return previous.size + Int64(fraction * CGFloat(next.size - previous.size))
            }
        }
        return stops[stops.count - 1].size
    }

    func configure(size: Int64, onChange: @escaping (Int64) -> Void) {
        self.onChange = onChange
        slider.value = Float(Self.position(for: size))
        updateText(size)
    }

    private func sliderMoved() {
        let size = Self.size(for: CGFloat(slider.value))
        updateText(size)
        onChange?(size)
    }

    private func updateText(_ size: Int64) {
        textLabelView.text = L10n.telegram("AutoDownloadSettings.UpTo", MediaAutoDownload.sizeString(size))
    }
}
