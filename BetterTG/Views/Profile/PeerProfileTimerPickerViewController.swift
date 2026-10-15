// PeerProfileTimerPickerViewController.swift

import UIKit

// MARK: - PeerProfileTimerPickerViewController

/// Telegram's ChatTimerScreen as the profile opens it. Mute until… (`.mute`) picks a date and time from now on, and
/// its button reads "Mute until …" once the date is ahead. Auto-Delete Other… (`.autoremove`) picks one of
/// Telegram's periods, starting on the closest one not above the current timer, with Disable Auto-Delete while a timer
/// is set.
final class PeerProfileTimerPickerViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    enum Mode {
        /// Called with the seconds left until the picked date.
        case muteUntil(onApply: (Int) -> Void)
        /// Called with the picked period in seconds, or 0 to disable the timer.
        case autoDelete(current: Int, format: (Int) -> String, onApply: (Int) -> Void)
    }

    /// ChatTimerScreen's autoremoveTimerValues.
    static let autoDeleteValues: [Int] = {
        let day = 24 * 60 * 60
        return [1, 2, 3, 4, 5, 6].map { $0 * day }
            + [1, 2, 3].map { $0 * 7 * day }
            + [31, 60, 93, 120, 155, 180, 365].map { $0 * day }
    }()

    private let mode: Mode
    private let datePicker = UIDatePicker()
    private let valuePicker = UIPickerView()
    private let primaryButton = UIButton(configuration: .filled())
    private let secondaryButton = UIButton(configuration: .plain())

    /// Seconds from now to the picked date; zero once it is not ahead.
    private var muteInterval: Int {
        max(0, Int(datePicker.date.timeIntervalSinceNow.rounded()))
    }

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"), style: .plain, target: self, action: #selector(cancelPressed),
        )

        let picker: UIView
        var showsDisable = false
        switch mode {
        case .muteUntil:
            title = L10n.telegram("Conversation.Mute.SetupTitle")
            datePicker.datePickerMode = .dateAndTime
            datePicker.preferredDatePickerStyle = .wheels
            datePicker.minimumDate = Foundation.Date()
            datePicker.date = Foundation.Date()
            datePicker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
            picker = datePicker
        case .autoDelete(let current, _, _):
            title = L10n.telegram("Conversation.DeleteTimer.SetupTitle")
            valuePicker.dataSource = self
            valuePicker.delegate = self
            valuePicker.selectRow(Self.initialRow(current: current), inComponent: 0, animated: false)
            picker = valuePicker
            showsDisable = current > 0
        }
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)

        primaryButton.configuration?.cornerStyle = .large
        primaryButton.configuration?.buttonSize = .large
        primaryButton.addTarget(self, action: #selector(primaryPressed), for: .touchUpInside)
        secondaryButton.configuration?.title = L10n.telegram("Conversation.DeleteTimer.Disable")
        secondaryButton.configuration?.baseForegroundColor = .systemRed
        secondaryButton.configuration?.buttonSize = .large
        secondaryButton.addTarget(self, action: #selector(secondaryPressed), for: .touchUpInside)
        secondaryButton.isHidden = !showsDisable
        let buttons = UIStackView(arrangedSubviews: [primaryButton, secondaryButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.axis = .vertical
        buttons.spacing = 4
        view.addSubview(buttons)
        updatePrimaryTitle()

        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            picker.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: picker.bottomAnchor, constant: 12),
            buttons.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    /// Telegram's stringForPreciseRelativeTimestamp: the time today, else the date and the time.
    static func preciseText(for date: Foundation.Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDateInToday(date) else { return time }
        return date.formatted(date: .numeric, time: .omitted) + ", " + time
    }

    /// ChatTimerScreen's selectionStrategy .closestLowerOrEqual.
    private static func initialRow(current: Int) -> Int {
        autoDeleteValues.lastIndex { $0 <= current } ?? 0
    }

    /// The sheet fits the picker and its buttons.
    func present(from host: UIViewController) {
        let navigation = UINavigationController(rootViewController: self)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.custom { context in min(context.maximumDetentValue, 440) }]
            sheet.prefersGrabberVisible = true
        }
        host.present(navigation, animated: true)
    }

    // MARK: Picker

    func numberOfComponents(in _: UIPickerView) -> Int {
        1
    }

    func pickerView(_: UIPickerView, numberOfRowsInComponent _: Int) -> Int {
        Self.autoDeleteValues.count
    }

    func pickerView(_: UIPickerView, titleForRow row: Int, forComponent _: Int) -> String? {
        guard case .autoDelete(_, let format, _) = mode else { return nil }
        return format(Self.autoDeleteValues[row])
    }

    private func updatePrimaryTitle() {
        primaryButton.configuration?.title =
            switch mode {
            case .muteUntil:
                muteInterval > 0
                    ? L10n.telegram("Conversation.Mute.ApplyMuteUntil", Self.preciseText(for: datePicker.date))
                    : L10n.telegram("Common.Close")
            case .autoDelete:
                L10n.telegram("Conversation.DeleteTimer.Apply")
            }
    }

    @objc private func dateChanged() {
        updatePrimaryTitle()
    }

    @objc private func cancelPressed() {
        dismiss(animated: true)
    }

    @objc private func primaryPressed() {
        switch mode {
        case .muteUntil(let onApply):
            let seconds = muteInterval
            dismiss(animated: true) { if seconds > 0 { onApply(seconds) } }
        case .autoDelete(_, _, let onApply):
            let seconds = Self.autoDeleteValues[valuePicker.selectedRow(inComponent: 0)]
            dismiss(animated: true) { onApply(seconds) }
        }
    }

    @objc private func secondaryPressed() {
        guard case .autoDelete(_, _, let onApply) = mode else { return }
        dismiss(animated: true) { onApply(0) }
    }
}
