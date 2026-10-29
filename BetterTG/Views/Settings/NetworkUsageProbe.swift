// NetworkUsageProbe.swift

#if DEBUG
import TDLibKit
import UIKit

/// The real statistics controller with local bytes. Reads and Reset never reach TDLib in this fixture.
@MainActor enum NetworkUsageProbe {
    private struct Failure: Error, CustomStringConvertible { let description: String }

    private final class Host: UIViewController {
        private let status = UILabel()
        private var opened = false

        override func viewDidLoad() {
            super.viewDidLoad()
            title = "Network usage fixture"
            view.backgroundColor = .systemGroupedBackground
            let controls = UIStackView()
            controls.axis = .vertical
            controls.spacing = 18
            controls.translatesAutoresizingMaskIntoConstraints = false
            for title in ["Open statistics", "Appearance"] {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    if title == "Open statistics" { showStatistics() }
                    else if let navigation = navigationController {
                        navigation.overrideUserInterfaceStyle = navigation.traitCollection.userInterfaceStyle == .dark
                            ? .light
                            : .dark
                    }
                }, for: .touchUpInside)
                controls.addArrangedSubview(button)
            }
            status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            status.numberOfLines = 0
            status.textAlignment = .center
            controls.addArrangedSubview(status)
            view.addSubview(controls)
            NSLayoutConstraint.activate([
                controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
                controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
            let result: String
            do {
                try verify()
                result = "Network usage probe passed: All/Mobile/Wifi; roaming/other; no-network exclusion; repeated selection; totals"
            } catch {
                result = "Network usage probe failed: \(error)"
            }
            status.text = result
            log(result)
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("network-usage-probe.txt"),
                    options: .atomic,
                )
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !opened else { return }
            opened = true
            showStatistics()
        }

        private func showStatistics() {
            navigationController?.pushViewController(
                NetworkUsageViewController(probeStatistics: statistics),
                animated: true,
            )
        }
    }

    private static var statistics: TDNativeNetworkStatistics {
        .init(sinceDate: 1_700_000_000, entries: [
            .networkStatisticsEntryFile(.init(
                fileType: .fileTypePhoto,
                networkType: .networkTypeMobile,
                sentBytes: 100,
                receivedBytes: 200,
            )),
            .networkStatisticsEntryFile(.init(
                fileType: .fileTypeVoiceNote,
                networkType: .networkTypeMobileRoaming,
                sentBytes: 300,
                receivedBytes: 400,
            )),
            .networkStatisticsEntryFile(.init(
                fileType: .fileTypePhoto,
                networkType: .networkTypeWiFi,
                sentBytes: 500,
                receivedBytes: 600,
            )),
            .networkStatisticsEntryCall(.init(
                networkType: .networkTypeOther,
                sentBytes: 700,
                receivedBytes: 800,
                duration: 1,
            )),
            .networkStatisticsEntryFile(.init(
                fileType: nil,
                networkType: .networkTypeNone,
                sentBytes: 900,
                receivedBytes: 1000,
            )),
        ])
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-network-usage") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let navigation = TelegramNavigationController(rootViewController: Host())
            navigation.modalPresentationStyle = .fullScreen
            window.rootViewController?.present(navigation, animated: false)
        }
    }

    private static func require(_ value: Bool, _ reason: String) throws {
        guard value else { throw Failure(description: reason) }
    }

    private static func verify() throws {
        let controller = NetworkUsageViewController(probeStatistics: statistics)
        controller.loadViewIfNeeded()
        guard let control = controller.navigationItem
.titleView?
.subviews
.compactMap({ $0 as? UISegmentedControl })
            .first
        else { throw Failure(description: "missing native segmented control") }
        try require(control.numberOfSegments == 3 && control.selectedSegmentIndex == 0, "All not initially selected")
        for (index, sent, received): (Int, Int64, Int64) in [
            (0, 1600, 2000),
            (1, 400, 600),
            (2, 1200, 1400),
            (0, 1600, 2000),
        ] {
            control.selectedSegmentIndex = index
            control.sendActions(for: .valueChanged)
            let sections = controller.sections
            try require(sections.count == 8, "categories/total/reset changed")
            try require(
                sections[6].rows.map(\.detail) == [
                    SettingsFormatting.byteCount(sent),
                    SettingsFormatting.byteCount(received),
                ],
                "wrong totals for mode \(index)",
            )
        }
        try require(
            controller.sections[1].rows.map(\.detail) == [
                SettingsFormatting.byteCount(600),
                SettingsFormatting.byteCount(800),
            ],
            "All photos should combine mobile and Wi-Fi",
        )
        try require(
            controller.sections[0].rows.allSatisfy { $0.detail == SettingsFormatting.byteCount(0) },
            "networkTypeNone leaked into messages",
        )
    }
}
#endif
