// HeaderPanelsProbe.swift

#if DEBUG
import UIKit

/// Account-free fixture for the shared panel's stacking, interruption, live glass hierarchy and actions.
/// It never starts playback, changes Media preferences or broadcasts a location.
@MainActor enum HeaderPanelsProbe {
    private final class Controller: UIViewController {
        private let panels = TelegramHeaderPanelsView()
        private let background = TelegramBarBackgroundView(edge: .top)
        private let modes = UISegmentedControl(items: ["Voice", "Location", "Both", "Hidden"])
        private let status = UILabel()
        private var isPlaying = false
        private var rate: Float = 1
        private var isMusic = false
        private var events = [String]()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemGroupedBackground
            view.addSubview(background)
            view.addSubview(panels)
            modes.selectedSegmentIndex = 2
            modes.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
            view.addSubview(modes)
            let actions = UIStackView()
            actions.axis = .vertical
            actions.spacing = 12
            for (title, action) in [
                ("Interrupt collapse", { [weak self] in self?.interrupt() }),
                ("Toggle music", { [weak self] in
                    self?.isMusic.toggle()
                    self?.configureVoice()
                    self?.view.layoutIfNeeded()
                    self?.inspect()
                }),
                ("Toggle appearance", { [weak self] in
                    guard let self else { return }
                    overrideUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .light : .dark
                }),
            ] {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
                actions.addArrangedSubview(button)
            }
            actions.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(actions)
            status.numberOfLines = 0
            status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            status.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(status)
            NSLayoutConstraint.activate([
                actions.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 220),
                actions.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                status.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 20),
                status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                status.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            ])
            panels.voiceHeader.onTogglePlayback = { [weak self] in
                self?.isPlaying.toggle()
                self?.configureVoice()
                self?.record("play/pause")
            }
            panels.voiceHeader.onCycleRate = { [weak self] in
                guard let self else { return }
                rate = rate == 2 ? 1 : rate + 0.5
                configureVoice()
                record("rate")
            }
            panels.voiceHeader.onOpen = { [weak self] in self?.record("open media") }
            panels.voiceHeader.onPlayNext = { [weak self] in self?.record("next") }
            panels.voiceHeader.onPlayPrevious = { [weak self] in self?.record("previous") }
            panels.voiceHeader.onClose = { [weak self] in self?.show(voice: false, location: true) }
            panels.liveLocationPanel.onOpen = { [weak self] in self?.record("open location") }
            panels.liveLocationPanel.onClose = { [weak self] in
                guard let self else { return }
                present(LiveLocationPanelView.stopSheet(sourceView: panels.liveLocationPanel) { [weak self] in
                    self?.show(voice: true, location: false)
                    self?.record("fixture stop location")
                }, animated: true)
            }
            panels.liveLocationPanel.configure(subtitle: "Sharing with Parity fixture", isAccent: false)
            configureVoice()
            show(voice: true, location: true, animated: false)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            panels.frame = CGRect(
                x: 0,
                y: view.safeAreaInsets.top + 54,
                width: view.bounds.width,
                height: panels.contentHeight,
            )
            background.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: panels.frame.maxY)
            modes.frame = CGRect(x: 16, y: view.safeAreaInsets.top + 165, width: view.bounds.width - 32, height: 32)
        }

        private func configureVoice() {
            panels.voiceHeader.configure(.init(
                title: isMusic
                ? "A long music title with its playback rate hidden"
                : "Ada Lovelace",
                subtitle: isMusic ? "Parity artist" : "Voice Message",
                isPlaying: isPlaying,
                progress: 0.4,
                rate: rate,
                showsRate: !isMusic,
                isMusic: isMusic,
            ))
        }

        @objc private func modeChanged() {
            let mode = modes.selectedSegmentIndex
            show(voice: mode == 0 || mode == 2, location: mode == 1 || mode == 2)
        }

        private func show(voice: Bool, location: Bool, animated: Bool = true) {
            modes.selectedSegmentIndex = voice ? (location ? 2 : 0) : (location ? 1 : 3)
            panels.setVisiblePanels(voice: voice, liveLocation: location)
            let changes = {
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
            }
            if animated {
                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction],
                    animations: changes,
                )
            } else { changes() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.inspect() }
        }

        private func interrupt() {
            show(voice: false, location: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                self?.show(voice: false, location: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.show(voice: true, location: true)
            }
        }

        private func record(_ event: String) {
            events.append(event)
            inspect()
        }

        private func inspect() {
            func descendants(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(descendants) }
            let glass = descendants(panels)
.compactMap { $0 as? UIVisualEffectView }
                .first { $0.effect is UIGlassEffect }
            let interactive = (glass?.effect as? UIGlassEffect)?.isInteractive == true
            let controls = descendants(panels).compactMap { $0 as? UIControl }.filter { control in
                guard !control.isHidden, !control.bounds.isEmpty else { return false }
                let point = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: panels)
                guard let hit = panels.hitTest(point, with: nil) else { return false }
                return hit === control || hit.isDescendant(of: control)
            }
            let liveHits = controls.allSatisfy { control in
                let point = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: panels)
                guard let hit = panels.hitTest(point, with: nil), let glass else { return false }
                return hit.isDescendant(of: glass.contentView)
            }
            status.text = "height: \(Int(panels.bounds.height)); controls: \(controls.count)\ninteractive glass: \(interactive); hits inside: \(liveHits)\n\(events.suffix(5).joined(separator: ", "))"
        }
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-header-panels") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let controller = Controller()
            controller.modalPresentationStyle = .fullScreen
            window.rootViewController?.present(controller, animated: false)
        }
    }
}
#endif
